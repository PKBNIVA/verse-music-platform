require "test_helper"

class MessagingNotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @seq = 0
    clear_enqueued_jobs
  end

  test "inbox names the counterpart by conversation side, not by account role" do
    hiring_jobseeker = create_user("Hiring Artist", "jobseeker")
    talent = create_user("Session Talent", "jobseeker")
    job = create_job(hiring_jobseeker)
    Application.create!(job:, candidate: talent)

    post "/api/conversations", params: { candidateId: talent.id, jobId: job.id }, headers: auth(hiring_jobseeker), as: :json
    assert_response :created
    conversation_id = response.parsed_body.fetch("id")

    get "/api/conversations", headers: auth(hiring_jobseeker)
    row = response.parsed_body.fetch("conversations").find { _1["id"] == conversation_id }
    assert_equal ["Session Talent", talent.id, "employer"], row.values_at("counterpartName", "counterpartId", "viewerSide")
    assert_equal job.title, row["jobTitle"]

    get "/api/conversations", headers: auth(talent)
    row = response.parsed_body.fetch("conversations").find { _1["id"] == conversation_id }
    assert_equal ["Hiring Artist", hiring_jobseeker.id, "candidate"], row.values_at("counterpartName", "counterpartId", "viewerSide")
  end

  test "messages validate body, keep emoji and markup verbatim, and report read receipts and unread counts" do
    employer = create_user("Receipt Employer", "employer")
    candidate = create_user("Receipt Candidate", "jobseeker")
    conversation = Conversation.create!(candidate:, employer:)
    path = "/api/conversations/#{conversation.id}/messages"

    [nil, "", "   \n\t "].each do |body|
      post path, params: { body: }, headers: auth(employer), as: :json
      assert_response :unprocessable_entity
      assert_equal "MESSAGE_EMPTY", response.parsed_body["code"]
    end
    post path, params: { body: "x" * (MessagesController::MAX_LENGTH + 1) }, headers: auth(employer), as: :json
    assert_response :unprocessable_entity
    assert_equal "MESSAGE_TOO_LONG", response.parsed_body["code"]
    assert_equal 0, conversation.messages.count

    long = "y" * MessagesController::MAX_LENGTH
    xss = %(<img src=x onerror="alert(1)"><script>alert(2)</script>)
    ["  Hello 👋🏽 from the studio 🎸  ", xss, long].each do |body|
      post path, params: { body: }, headers: auth(employer), as: :json
      assert_response :created
      assert_nil response.parsed_body.dig("message", "readAt")
    end
    assert_equal ["Hello 👋🏽 from the studio 🎸", xss, long], conversation.messages.order(:created_at).pluck(:body)

    get "/api/notifications/unread", headers: auth(candidate)
    assert_equal 3, response.parsed_body["unreadMessages"]
    get "/api/conversations", headers: auth(candidate)
    row = response.parsed_body.fetch("conversations").first
    assert_equal 3, row["unreadCount"]
    assert_equal false, row["lastMessageFromMe"]
    assert_equal ConversationsController::PREVIEW_LENGTH, row["lastMessage"].length
    get "/api/conversations", headers: auth(employer)
    assert_equal [0, true], response.parsed_body.fetch("conversations").first.values_at("unreadCount", "lastMessageFromMe")

    # The sender's own view does not mark anything read.
    get path, headers: auth(employer)
    assert response.parsed_body.fetch("messages").all? { _1["readAt"].nil? }

    get path, headers: auth(candidate)
    assert_response :success
    assert_equal false, response.parsed_body["truncated"]
    get path, headers: auth(employer)
    assert response.parsed_body.fetch("messages").all? { _1["readAt"].present? }, "sender sees read receipts"
    get "/api/notifications/unread", headers: auth(candidate)
    assert_equal [0, 0], response.parsed_body.values_at("unread", "unreadMessages")

    outsider = create_user("Receipt Outsider", "jobseeker")
    get path, headers: auth(outsider)
    assert_response :not_found
    post path, params: { body: "hi" }, headers: auth(outsider), as: :json
    assert_response :not_found
    get "/api/conversations/missing/messages", headers: auth(employer)
    assert_response :not_found
  end

  test "history reports truncation beyond the cap" do
    employer = create_user("Cap Employer", "employer")
    candidate = create_user("Cap Candidate", "jobseeker")
    conversation = Conversation.create!(candidate:, employer:)
    base = 1.day.ago
    Message.insert_all!(Array.new(MessagesController::HISTORY_LIMIT) do |index|
      { id: SecureRandom.uuid, conversation_id: conversation.id, sender_id: employer.id, body: "bulk #{index}", created_at: base + index.seconds, updated_at: base }
    end)
    get "/api/conversations/#{conversation.id}/messages", headers: auth(candidate)
    assert_equal [false, 200], response.parsed_body.values_at("truncated", "limit")

    post "/api/conversations/#{conversation.id}/messages", params: { body: "newest" }, headers: auth(candidate), as: :json
    get "/api/conversations/#{conversation.id}/messages", headers: auth(candidate)
    body = response.parsed_body
    assert body["truncated"]
    assert_equal MessagesController::HISTORY_LIMIT, body["messages"].size
    assert_equal ["bulk 1", "newest"], [body["messages"].first["body"], body["messages"].last["body"]]
  end

  test "new messages raise one debounced notification per conversation and never copy the body" do
    employer = create_user("Debounce Employer", "employer")
    candidate = create_user("Debounce Candidate", "jobseeker")
    job = create_job(employer)
    conversation = Conversation.create!(candidate:, employer:, job:)
    other = Conversation.create!(candidate:, employer:)
    path = "/api/conversations/#{conversation.id}/messages"

    3.times { |i| post path, params: { body: "secret body #{i}" }, headers: auth(employer), as: :json }
    post "/api/conversations/#{other.id}/messages", params: { body: "other thread" }, headers: auth(employer), as: :json

    notes = candidate.notifications.where(kind: "message").order(:created_at)
    assert_equal 2, notes.count, "one per conversation"
    note = notes.find_by!(link: "/messages?c=#{conversation.id}")
    assert_equal "3 new messages from Debounce Employer", note.title
    assert_equal "About #{job.title}.", note.body
    assert_not_includes note.attributes.values.join(" "), "secret body"
    assert_equal 0, employer.notifications.count, "senders are not notified"

    get "/api/notifications", headers: auth(candidate)
    listed = response.parsed_body.fetch("notifications")
    assert_equal ["message", "message"], listed.pluck("type")
    assert_equal 2, response.parsed_body["unread"]

    # Opening the conversation reads its notification only.
    get path, headers: auth(candidate)
    assert note.reload.read_at
    assert_nil candidate.notifications.find_by!(link: "/messages?c=#{other.id}").read_at

    post path, params: { body: "after read" }, headers: auth(employer), as: :json
    assert_equal 1, candidate.notifications.where(link: "/messages?c=#{conversation.id}", read_at: nil).count
    assert_equal "New message from Debounce Employer", candidate.notifications.where(link: "/messages?c=#{conversation.id}", read_at: nil).first.title

    post "/api/conversations/#{conversation.id}/messages", params: { body: "reply" }, headers: auth(candidate), as: :json
    assert_equal ["/messages?c=#{conversation.id}"], employer.notifications.pluck(:link)
  end

  test "mark one and mark all notifications read" do
    user = create_user("Reader", "jobseeker")
    stranger = create_user("Stranger", "jobseeker")
    first = user.notifications.create!(kind: "booking", title: "One", link: "/bookings")
    user.notifications.create!(kind: "workspace", title: "Two")
    theirs = stranger.notifications.create!(kind: "booking", title: "Theirs")

    patch "/api/notifications/#{theirs.id}", params: {}, headers: auth(user), as: :json
    assert_response :not_found
    patch "/api/notifications/#{first.id}", params: {}, headers: auth(user), as: :json
    assert_response :success
    assert first.reload.read_at
    patch "/api/notifications/#{first.id}", params: { read: false }, headers: auth(user), as: :json
    assert_nil first.reload.read_at

    post "/api/notifications/read-all", headers: auth(user), as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["updated"]
    assert_equal 0, user.notifications.where(read_at: nil).count
    assert_nil theirs.reload.read_at, "only the viewer's notifications"

    post "/api/notifications/read-all", headers: auth(user), as: :json
    assert_equal 0, response.parsed_body["updated"]
    post "/api/notifications/read-all", as: :json
    assert_response :unauthorized
  end

  test "booking parties can open a conversation from the booking" do
    owner = create_user("Act Owner", "jobseeker")
    requester = create_user("Event Planner", "employer")
    outsider = create_user("Booking Outsider", "employer")
    booking = create_booking(owner:, requester:)

    post "/api/conversations", params: { bookingId: booking.id }, headers: auth(requester), as: :json
    assert_response :created
    conversation = Conversation.find(response.parsed_body.fetch("id"))
    assert_equal [owner.id, requester.id, nil], [conversation.candidate_id, conversation.employer_id, conversation.job_id]

    post "/api/conversations", params: { bookingId: booking.id }, headers: auth(owner), as: :json
    assert_equal conversation.id, response.parsed_body.fetch("id"), "same thread from either side"

    post "/api/conversations", params: { bookingId: booking.id }, headers: auth(outsider), as: :json
    assert_response :not_found
    post "/api/conversations", params: { bookingId: "missing" }, headers: auth(owner), as: :json
    assert_response :not_found

    requester.update!(status: "suspended")
    post "/api/conversations", params: { bookingId: booking.id }, headers: auth(owner), as: :json
    assert_response :forbidden
  end

  test "booking and application events notify the other side and queue emails only for verified recipients with a provider" do
    owner = create_user("Email Owner", "jobseeker", verified_email: true)
    requester = create_user("Email Requester", "employer", verified_email: true)
    act = Act.create!(owner:, name: "Email Ensemble", act_type: "band", status: "active", currency: "INR", fee_basis: "event")

    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
      post "/api/bookings", params: { actId: act.id, eventType: "wedding", eventDate: 30.days.from_now.to_date, city: "Mumbai" }, headers: auth(requester), as: :json
      assert_response :created
      booking = BookingRequest.find(response.parsed_body.fetch("id"))
      assert_equal ["booking", "/bookings"], owner.notifications.last.values_at(:kind, :link)
      assert_enqueued_with(job: NotificationEmailJob, args: [owner.id, "booking_enquiry", { "act" => "Email Ensemble", "name" => "Email Requester" }])

      clear_enqueued_jobs
      post "/api/bookings/#{booking.id}/status", params: { status: "viewed" }, headers: auth(owner), as: :json
      assert_response :success
      assert_equal "booking_status", requester.notifications.last.kind
      assert_equal "Email Ensemble: viewed by Email Owner.", requester.notifications.last.body
      assert_enqueued_with(job: NotificationEmailJob, args: [requester.id, "booking_status", { "act" => "Email Ensemble", "status" => "viewed" }])

      clear_enqueued_jobs
      post "/api/bookings/#{booking.id}/status", params: { status: "cancelled" }, headers: auth(requester), as: :json
      assert_equal ["booking_status", "Email Ensemble: cancelled by Email Requester."], owner.notifications.order(:created_at).last.values_at(:kind, :body)
      assert_enqueued_jobs 1, only: NotificationEmailJob

      clear_enqueued_jobs
      post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(requester), as: :json
      assert_response :conflict
      assert_no_enqueued_jobs

      employer = create_user("Status Employer", "employer")
      candidate = create_user("Status Candidate", "jobseeker", verified_email: true)
      job = create_job(employer)
      post "/api/jobs/#{job.id}/apply", params: { coverLetter: "Hello" }, headers: auth(candidate), as: :json
      assert_response :created
      application = Application.find(response.parsed_body.fetch("id"))
      assert_equal ["application", "/hiring/applicants"], employer.notifications.last.values_at(:kind, :link)
      assert_no_enqueued_jobs(only: NotificationEmailJob)

      patch "/api/employer/applications/#{application.id}", params: { status: "Shortlisted" }, headers: auth(employer), as: :json
      assert_response :success
      assert_equal ["application_status", "/jobseeker/applications"], candidate.notifications.last.values_at(:kind, :link)
      assert_enqueued_with(job: NotificationEmailJob, args: [candidate.id, "application_status", { "job" => job.title, "status" => "Shortlisted" }])

      clear_enqueued_jobs
      unverified = create_user("Unverified Candidate", "jobseeker")
      Application.create!(job:, candidate: unverified).tap do |row|
        patch "/api/employer/applications/#{row.id}", params: { status: "Rejected" }, headers: auth(employer), as: :json
      end
      assert_equal "application_status", unverified.notifications.last.kind
      assert_no_enqueued_jobs(only: NotificationEmailJob)
    end

    clear_enqueued_jobs
    booking = create_booking(owner:, requester:)
    post "/api/bookings/#{booking.id}/status", params: { status: "viewed" }, headers: auth(owner), as: :json
    assert_response :success
    assert_no_enqueued_jobs(only: NotificationEmailJob)
  end

  test "new message emails are sent at most once per conversation per hour" do
    employer = create_user("Hourly Employer", "employer", verified_email: true)
    candidate = create_user("Hourly Candidate", "jobseeker", verified_email: true)
    conversation = Conversation.create!(candidate:, employer:)
    path = "/api/conversations/#{conversation.id}/messages"

    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
      post path, params: { body: "private words" }, headers: auth(employer), as: :json
      assert_enqueued_with(job: NotificationEmailJob, args: [candidate.id, "new_message", { "name" => "Hourly Employer", "path" => "/messages?c=#{conversation.id}" }])
      enqueued_jobs.each { |job| assert_not_includes job.to_s, "private words" }

      clear_enqueued_jobs
      post path, params: { body: "second" }, headers: auth(employer), as: :json
      get path, headers: auth(candidate)
      post path, params: { body: "after reading, same hour" }, headers: auth(employer), as: :json
      assert_no_enqueued_jobs(only: NotificationEmailJob)

      travel 61.minutes do
        get path, headers: auth(candidate)
        post path, params: { body: "an hour later" }, headers: auth(employer), as: :json
        assert_enqueued_jobs 1, only: NotificationEmailJob
      end
    end
  end

  test "email preference is read and updated by the signed-in user and suppresses every notification email kind" do
    owner = create_user("Optout Owner", "jobseeker", verified_email: true)
    requester = create_user("Optout Requester", "employer", verified_email: true)

    get "/api/notifications/preferences", headers: auth(owner)
    assert_equal({ "emailNotifications" => true }, response.parsed_body)
    [nil, "false", 0, "no"].each do |value|
      patch "/api/notifications/preferences", params: { emailNotifications: value }, headers: auth(owner), as: :json
      assert_response :bad_request
      assert_equal "INVALID_PREFERENCE", response.parsed_body["code"]
    end
    patch "/api/notifications/preferences", params: { emailNotifications: false }, headers: auth(owner), as: :json
    assert_equal({ "emailNotifications" => false }, response.parsed_body)
    assert_not owner.profile.reload.email_notifications
    get "/api/me", headers: auth(owner)
    assert_not response.parsed_body["user"].key?("emailNotifications"), "not part of public profile JSON"
    get "/api/notifications/preferences"
    assert_response :unauthorized

    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
      booking = create_booking(owner:, requester:)
      conversation = Conversation.create!(candidate: owner, employer: requester)
      job = create_job(requester)
      application = Application.create!(job:, candidate: owner)

      Notifier.booking_enquiry(booking)
      Notifier.booking_quote(create_booking(owner: requester, requester: owner))
      post "/api/bookings/#{booking.id}/status", params: { status: "negotiating" }, headers: auth(requester), as: :json
      post "/api/conversations/#{conversation.id}/messages", params: { body: "hi" }, headers: auth(requester), as: :json
      patch "/api/employer/applications/#{application.id}", params: { status: "Shortlisted" }, headers: auth(requester), as: :json
      assert_response :success
      assert_operator owner.notifications.count, :>=, 4, "in-app notifications still arrive"
      assert_no_enqueued_jobs(only: NotificationEmailJob)

      # The other side kept the default and is still emailed.
      post "/api/bookings/#{booking.id}/status", params: { status: "declined" }, headers: auth(owner), as: :json
      assert_enqueued_with(job: NotificationEmailJob, args: [requester.id, "booking_status", { "act" => booking.act.name, "status" => "declined" }])

      clear_enqueued_jobs
      patch "/api/notifications/preferences", params: { emailNotifications: true }, headers: auth(owner), as: :json
      fresh = Conversation.create!(candidate: owner, employer: requester, job:)
      post "/api/conversations/#{fresh.id}/messages", params: { body: "again" }, headers: auth(requester), as: :json
      assert_enqueued_jobs 1, only: NotificationEmailJob
    end
  end

  test "one-click unsubscribe accepts only a valid, purpose-scoped token and needs no sign-in" do
    user = create_user("Unsub User", "employer", verified_email: true)
    other = create_user("Unsub Other", "jobseeker", verified_email: true)
    token = NotificationEmail.unsubscribe_token(user)

    tampered = token.sub(/.\z/) { _1 == "a" ? "b" : "a" }
    other_purpose = NotificationEmail.unsubscribe_verifier.generate(user.id, purpose: :password_reset)
    signed_id = user.signed_id(purpose: NotificationEmail::UNSUBSCRIBE_PURPOSE)
    other_verifier = Rails.application.message_verifier("somewhere-else").generate(user.id, purpose: NotificationEmail::UNSUBSCRIBE_PURPOSE)
    [nil, "", "garbage", tampered, other_purpose, signed_id, other_verifier, "#{token}x"].each do |bad|
      post "/api/notifications/unsubscribe", params: { token: bad }, as: :json
      assert_response :bad_request, bad.inspect
      assert_equal "INVALID_TOKEN", response.parsed_body["code"]
    end
    assert user.profile.reload.email_notifications

    # RFC 8058: the provider POSTs "List-Unsubscribe=One-Click" as a form to the URL carrying the token.
    post "/api/notifications/unsubscribe?token=#{CGI.escape(token)}", params: { "List-Unsubscribe" => "One-Click" }
    assert_response :success
    assert_equal({ "ok" => true, "emailNotifications" => false }, response.parsed_body)
    assert_not user.profile.reload.email_notifications
    assert other.profile.reload.email_notifications, "only the named user"

    user.profile.update!(email_notifications: true)
    get "/api/notifications/unsubscribe", params: { token: }
    assert_response :success
    assert_not user.profile.reload.email_notifications
    get "/api/notifications/unsubscribe", params: { token: }
    assert_response :success, "idempotent"

    admin = User.create!(name: "Unsub Admin", email: "unsub-admin-#{SecureRandom.hex(3)}@example.com", password: "StrongPass123!", role: "admin", status: "active")
    post "/api/notifications/unsubscribe", params: { token: NotificationEmail.unsubscribe_token(admin) }, as: :json
    assert_response :success
    assert_not admin.reload.profile.email_notifications, "profile-less accounts get a row"
  end

  test "transactional emails ignore the notification opt-out" do
    user = create_user("Transactional User", "jobseeker", verified_email: true)
    user.profile.update!(email_notifications: false)
    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
      post "/api/auth/forgot-password", params: { email: user.email }, as: :json
      assert_enqueued_jobs 1, only: EmailDeliveryJob
    end
  end

  private

  def create_user(name, role, verified_email: false)
    @seq += 1
    User.create!(name:, email: "msg-#{@seq}-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role:, status: "active",
      profile_complete: true, email_verified: verified_email).tap { _1.create_profile! }
  end

  def create_job(employer)
    Job.create!(employer:, title: "Messaging Opportunity #{@seq}", company: employer.name, location: "Mumbai", kind: "Contract", genre: "Pop",
      description: "A properly documented professional opportunity with clear responsibilities, written terms and collaborative production support.",
      status: "published")
  end

  def create_booking(owner:, requester:)
    act = Act.create!(owner:, name: "Booking Act #{@seq}", act_type: "band", status: "active", currency: "INR", fee_basis: "event")
    BookingRequest.create!(act:, requester:, event_type: "wedding", event_date: 30.days.from_now.to_date, city: "Mumbai", currency: "INR", status: "requested")
  end

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
