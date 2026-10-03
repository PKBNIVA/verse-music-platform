class UrgentRequestsController < ApplicationController
  include UserRateLimit

  # Each request alerts matching musicians (in-app, email, WhatsApp), so posting is capped per account.
  CREATES_PER_HOUR = 10
  # The token-based one-click action from the expiry-warning email carries its own signed
  # authorization (UrgentActionToken) and is not necessarily hit by a signed-in session.
  before_action -> { authenticate!("jobseeker", "employer") }, except: :action_from_token
  LIST_LIMIT = 200

  PAGE_SIZE = 20
  MAX_PAGE = 1_000
  SCOPES = %w[mine matches browse].freeze
  # Words that say nothing about which instrument or job someone does.
  ROLE_FILLER = %w[player artist artiste musician and the of].freeze

  # Three views of the same table (J-11), each paged PAGE_SIZE at a time:
  #   mine     requests the signed-in person posted, newest first
  #   matches  open requests from others that fit their roles and city (or that they were alerted about)
  #   browse   every open request from others
  # Without a scope a musician gets their matches and a hirer their own requests.
  def index
    return render_error("Filters must be plain text.", :bad_request, "INVALID_PARAMETER") unless [params[:city], params[:role], params[:scope], params[:page]].all? { _1.nil? || _1.is_a?(String) }
    scope_name = params[:scope].presence || (current_user.jobseeker? ? "matches" : "mine")
    return render_error("Unknown view.", :bad_request, "INVALID_PARAMETER") unless SCOPES.include?(scope_name)

    page = params[:page].to_i.clamp(1, MAX_PAGE)
    base = UrgentRequest.includes(:urgent_request_responses, :filled_by, requester: :profile)
    base = scope_name == "mine" ? base.where(requester: current_user).order(created_at: :desc) : base.open_and_recent.where.not(requester_id: current_user.id).order(start_at: :asc)
    base = base.where("city ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:city])}%") if params[:city].present?
    if params[:role].present?
      role = "%#{ActiveRecord::Base.sanitize_sql_like(params[:role])}%"
      base = base.where("role_name ILIKE :role OR instrument ILIKE :role OR title ILIKE :role", role:)
    end
    if scope_name == "matches"
      # Fit is decided in Ruby (word-for-word, never by substring), over the soonest LIST_LIMIT open requests.
      pool = base.limit(LIST_LIMIT).to_a
      reasons = alert_reasons(pool)
      matched = pool.select { matches_me?(_1, reasons) }
      total = matched.size
      items = matched.slice((page - 1) * PAGE_SIZE, PAGE_SIZE) || []
    else
      total = base.count
      items = base.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).to_a
      reasons = alert_reasons(items)
    end
    responded = UrgentRequestResponse.where(user: current_user, urgent_request_id: items.map(&:id)).pluck(:urgent_request_id).to_set
    @threads = threads_with(items.map(&:requester_id).uniq)
    render json: { requests: items.map { |item| serialize(item, responded, reasons[item.id]) }, scope: scope_name,
      page:, perPage: PAGE_SIZE, total:, hasMore: total > page * PAGE_SIZE }
  end

  # The confirmation/status screen for one request: how many musicians were notified and how
  # many responded so far. Only the requester can see it (their own live status card).
  def show
    item = UrgentRequest.where(requester: current_user).includes(:urgent_request_responses).find(params[:id])
    render json: { request: serialize(item, Set.new), responseTimePromise: UrgentConfig.response_time_promise }
  end

  # The five required answers are the role, when, the city, a budget band and a short note; the
  # rest (venue, end time, instrument, requirements) is optional. The title is optional too: it
  # is written from the role and city when the client sends none. Every problem is returned at once.
  def create
    return unless within_user_rate_limit?("urgent-request-create", limit: CREATES_PER_HOUR, period: 1.hour)
    role, city = params[:roleName], params[:city]
    title = params[:title].presence || ("#{role} needed in #{city}" if role.is_a?(String) && city.is_a?(String) && role.present? && city.present?)
    item = UrgentRequest.new(requester: current_user, title:, role_name: role, instrument: params[:instrument],
      city:, start_at: params[:startAt], end_at: params[:endAt], budget_min: params[:budgetMin], budget_max: params[:budgetMax],
      currency: params[:currency].presence || "INR", genre: params[:genre], requirements: requirements_text,
      travel_covered: params[:travelCovered] || false, status: "open")
    item.validate
    # The title is written from the role and city, so a missing one is reported on those fields only.
    item.errors.delete(:title) if params[:title].blank?
    item.errors.add(:start_at, "can't be in the past") if item.start_at && item.start_at < 1.minute.ago
    item.errors.add(:budget, "is required: choose a budget band") if item.budget_min.nil? && item.budget_max.nil?
    item.errors.add(:note, "is required: tell them what to expect") if requirements_text.blank?
    return render_record_invalid(ActiveRecord::RecordInvalid.new(item)) if item.errors.any?

    item.save!
    # Matching and the alert fan-out are CPU-bound, so they run in UrgentMatchJob, enqueued only now that the
    # row is committed. The status card polls GET /urgent-requests/:id for matchStatus and the notified count.
    begin
      UrgentMatchJob.perform_later(item.id)
    rescue => e
      # The row is saved; UrgentMatchSweepJob picks it up. A 500 here would invite a duplicate post.
      ErrorReporter.capture(e, tags: { source: "urgent_match_enqueue" }, urgent_request_id: item.id)
      Rails.logger.error("UrgentMatchJob enqueue failed for urgent request #{item.id}: #{e.class}")
    end
    render json: { id: item.id, notifiedCount: 0, matchStatus: "pending", responseTimePromise: UrgentConfig.response_time_promise }, status: :created
  end

  def respond
    item = UrgentRequest.where(status: "open").find(params[:id]); return render_error("You cannot respond to your own request.", :conflict) if item.requester_id == current_user.id
    return render_error("Keep your note under 1,000 characters.", :unprocessable_content) if params[:message].to_s.length > 1_000
    rate = params[:rate].presence
    return render_error("Rate must be a whole number of 0 or more.", :unprocessable_content) if rate && !rate.to_s.match?(/\A\d{1,9}\z/)
    first_response = !UrgentRequestResponse.exists?(urgent_request_id: item.id, user_id: current_user.id)
    note = params[:message].to_s.strip.presence
    UrgentRequestResponse.upsert({ urgent_request_id: item.id, user_id: current_user.id, message: note, rate: rate&.to_i, status: "available", created_at: Time.current, updated_at: Time.current }, unique_by: :idx_urgent_response_unique)
    Realtime.urgent_request_changed(item, "response")
    Notifier.milestone_first_urgent_response(current_user, item)
    # The conversation exists from the first response, so the musician can open it at once (J-03).
    # The hirer gets one notice for the response, which opens that conversation; the note the
    # musician wrote is its first message, but only the email (not a second in-app notice) tells
    # the hirer about it.
    conversation = open_thread(item.requester, current_user, note: (note if first_response))
    response_link = conversation ? Notifier.message_link(conversation) : urgent_link(item.requester)
    Notification.create!(user: item.requester, kind: "urgent_response", title: "Availability response", body: "#{current_user.name} responded to #{item.title}.", link: response_link)
    Notifier.urgent_response_push(item, current_user, link: response_link) if first_response
    render json: { ok: true, conversationId: conversation&.id }, status: :created
  end

  def responses
    item = UrgentRequest.where(requester: current_user).find(params[:id]); render json: { responses: item.urgent_request_responses.includes(user: :profile).order(created_at: :desc).limit(LIST_LIMIT).map { _1.attributes.merge(name: _1.user.name, headline: _1.user.profile&.headline, photoUrl: _1.user.profile&.photo_url) } }
  end

  # The hirer picks one of the people who said they are available: the request is filled by them, both
  # get an in-app notice that leads to the conversation, and nothing is posted publicly (J-03).
  def accept
    item = UrgentRequest.where(requester: current_user).find(params[:id])
    response = item.urgent_request_responses.find_by(user_id: params[:userId].to_s)
    return render_error("Only someone who responded can be chosen for this request.", :unprocessable_content) unless response
    chosen = response.user
    conversation = nil
    item.with_lock do
      return render_error("This request is already #{item.status == 'filled' ? 'filled' : 'closed'}.", :conflict) unless item.open?

      item.update!(status: "filled", filled_by_id: chosen.id)
      UrgentRequestResponse.where(urgent_request_id: item.id, user_id: chosen.id).update_all(status: "accepted", updated_at: Time.current)
    end
    conversation = open_thread(current_user, chosen)
    # Each person's notice opens the conversation, or their own urgent-requests page when there is none.
    thread = conversation && Notifier.message_link(conversation)
    Notification.create!(user: chosen, kind: "urgent_accepted", title: "You were chosen", body: "#{current_user.name} chose you for #{item.title}. Message them to confirm the details.", link: thread || urgent_link(chosen))
    Notification.create!(user: current_user, kind: "urgent_accepted", title: "Request filled", body: "Request filled by #{chosen.name}: #{item.title}.", link: thread || urgent_link(current_user))
    Notifier.milestone_5th_filled_request(current_user)
    audit!("urgent_request.accept", item)
    render json: { ok: true, request: serialize(item.reload, Set.new), conversationId: conversation&.id }
  end

  def update
    item = UrgentRequest.where(requester: current_user).find(params[:id])
    return render_error("Invalid status", :bad_request) unless %w[filled cancelled closed].include?(params[:status])
    if params[:status] == "filled" && params[:filledByUserId].present?
      return render_error("Only someone who responded can be marked as filling this request.", :unprocessable_content) unless item.urgent_request_responses.exists?(user_id: params[:filledByUserId])
      item.update!(status: "filled", filled_by_id: params[:filledByUserId])
      Notifier.milestone_5th_filled_request(current_user)
    else
      item.update!(status: params[:status])
    end
    render json: { ok: true, request: serialize(item.reload, Set.new) }
  end

  # The one-click link in the expiry-warning email: GET .../urgent-requests/:id/token-action?action=filled|close&t=...
  # Requires no session; the signed token is the authorization. Marks the request filled
  # (with no particular responder chosen — the hirer can still pick one later on the request
  # page) or closed.
  def action_from_token
    # The action is read from the signed token itself (not from the "action" query param,
    # which Rails already reserves for the controller action name), so the token is the sole
    # source of authorization: it can only ever do what it was issued to do.
    payload = UrgentActionToken.verify(params[:t])
    return render_error("This link has expired or is invalid.", :unprocessable_content, "INVALID_TOKEN") unless payload
    return render_error("This link has expired or is invalid.", :unprocessable_content, "INVALID_TOKEN") unless payload["id"] == params[:id]

    item = UrgentRequest.find_by(id: payload["id"])
    return render_error("Request not found.", :not_found) unless item
    item.update!(status: payload["action"] == "filled" ? "filled" : "closed") if item.open?
    render json: { ok: true, status: item.status }
  end

  private

  # {other person's id => id of the newest conversation with them} for the signed-in user, so a
  # request already answered links straight to its thread.
  def threads_with(user_ids)
    Conversation.where(candidate_id: current_user.id, employer_id: user_ids).or(Conversation.where(employer_id: current_user.id, candidate_id: user_ids))
      .order(:updated_at).to_h { |c| [c.counterpart_for(current_user).id, c.id] }
  end

  # {request id => reasons} for the requests this person was alerted about in the app.
  def alert_reasons(items)
    UrgentRequestNotification.where(user: current_user, urgent_request_id: items.map(&:id), channel: "in_app").pluck(:urgent_request_id, :reasons).to_h
  end

  # The one hirer-musician thread, with `note` as its first message when given. Nil when either side
  # has blocked the other or the account is gone: the response itself still counts.
  def open_thread(hirer, musician, note: nil)
    return nil if UserBlock.between?(hirer, musician) || !hirer.active? || !musician.active?

    conversation = Conversation.open_between!(candidate: musician, employer: hirer)
    if note
      message = conversation.messages.new(sender: musician, body: note.first(MessagesController::MAX_LENGTH)).tap { _1.flag_scam_signals; _1.save! }
      Notifier.new_message(message, in_app: false)
    end
    conversation
  end

  # The requester's own urgent-requests page (a workspace route; "/urgent-requests" is the API path).
  def urgent_link(user) = "#{NotificationEmail.workspace(user)}/urgent"

  def words(text) = text.to_s.downcase.scan(/[[:alnum:]]+/) - ROLE_FILLER

  # Alerted about it, or the request's role is one of theirs and it is in their city. Someone with no
  # roles yet is matched on the city alone, and someone with no city on the role alone.
  def matches_me?(item, alerted)
    return true if alerted.key?(item.id)

    profile = current_user.profile
    mine = Array(profile&.roles).concat(Array(profile&.instruments)).flat_map { words(_1) }.to_set
    wanted = (words(item.role_name) + words(item.instrument)).to_set
    role_ok = mine.empty? || wanted.intersect?(mine)
    place = profile&.location.to_s.downcase
    city_ok = place.blank? || item.city.to_s.downcase.then { |city| city.present? && place.include?(city) }
    role_ok && city_ok
  end

  # The note first, then the optional venue and extra requirements, in the one `requirements`
  # column. Older clients send only `requirements`, which then is the note.
  def requirements_text
    return @requirements_text if defined?(@requirements_text)

    note, venue, extra = %i[note venue requirements].map { params[_1].is_a?(String) ? params[_1].strip.presence : nil }
    @requirements_text = if note
      [note, venue && "Venue: #{venue}", extra && "Requirements: #{extra}"].compact.join("\n")
    else
      [extra, venue && "Venue: #{venue}"].compact.join("\n").presence
    end
  end

  # Columns only the founders (admin site) and, for delivery counts, the requester may see.
  INTERNAL_COLUMNS = %w[founder_notes expiry_warned_at].freeze
  DELIVERY_COLUMNS = %w[notified_count first_notified_at last_notified_at match_status matched_at].freeze

  def serialize(item, responded_ids, my_reasons = nil)
    hidden = item.requester_id == current_user.id ? INTERNAL_COLUMNS : INTERNAL_COLUMNS + DELIVERY_COLUMNS
    item.attributes.except(*hidden).merge(requesterName: item.requester.name, requesterVerified: item.requester.profile&.verified || false,
      myResponse: responded_ids.include?(item.id), responseCount: item.urgent_request_responses.size,
      myMatchReasons: my_reasons, filledByName: item.filled_by&.name, conversationId: @threads&.dig(item.requester_id))
  end
end
