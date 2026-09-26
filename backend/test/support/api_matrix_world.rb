# Shared fixture world and helpers for the API matrix suites (test/integration/api_*_test.rb).
#
# ApiMatrixWorld.build creates two users per marketplace role plus an admin, and gives every
# non-admin user a complete, symmetric set of owned resources so that a request can be replayed
# as the owner (allowed), as a different user of the same role (IDOR) and as the wrong role.
module ApiMatrixWorld
  PASSWORD = "MatrixPass123!".freeze
  MISSING_ID = "none_00000000-0000-4000-8000-000000000000".freeze
  ACTORS = %i[js js2 emp emp2 admin].freeze
  # The user of the same role whose resources an actor must never reach.
  PEER = { js: :js2, js2: :js, emp: :emp2, emp2: :emp }.freeze
  ROLE_OF = { js: "jobseeker", js2: "jobseeker", emp: "employer", emp2: "employer", admin: "admin" }.freeze

  class World
    attr_reader :users, :tokens, :refs

    def initialize
      @users = {}
      @tokens = {}
      @refs = Hash.new { |hash, key| hash[key] = {} }
    end

    def user(actor) = users.fetch(actor)
    def headers(actor) = actor.nil? ? {} : { "Authorization" => "Bearer #{tokens.fetch(actor)}" }

    # Resolves {token} placeholders against the owner's references, falling back to :shared.
    def path(template, owner)
      template.gsub(/\{(\w+)\}/) do
        key = Regexp.last_match(1).to_sym
        next MISSING_ID if key == :missing
        refs[owner][key] || refs[:shared].fetch(key) { raise KeyError, "no #{key} for #{owner} in #{template}" }
      end
    end
  end

  module_function

  def build
    world = World.new
    seq = 0
    make_user = lambda do |actor, name, role, profile: {}, complete: true|
      seq += 1
      user = User.create!(name:, email: "matrix-#{actor}-#{seq}-#{SecureRandom.hex(3)}@example.com", password: PASSWORD,
        role:, status: "active", profile_complete: complete, email_verified: true)
      user.create_profile!({ headline: "#{name} headline", location: "Mumbai", skills: ["Mixing"], roles: ["Engineer"] }.merge(profile)) unless role == "admin"
      raw = SecureRandom.urlsafe_base64(48)
      user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
      world.users[actor] = user
      world.tokens[actor] = raw
      user
    end

    make_user.call(:js, "Matrix Artist", "jobseeker")
    make_user.call(:js2, "Matrix Rival Artist", "jobseeker")
    make_user.call(:emp, "Matrix Studio", "employer", profile: { company_name: "Matrix Studio" })
    make_user.call(:emp2, "Matrix Rival Studio", "employer", profile: { company_name: "Rival Studio" })
    make_user.call(:admin, "Matrix Admin", "admin")
    hidden = make_user.call(:hidden, "Matrix Hidden", "jobseeker", complete: false)

    u = world.users
    %i[js js2 emp emp2].each do |actor|
      owner = u[actor]
      refs = world.refs[actor]
      refs[:self] = owner.id
      refs[:job] = create_job(owner, "published").id
      refs[:draft_job] = create_job(owner, "draft").id
      refs[:alert] = JobAlert.create!(user: owner, name: "Alert #{actor}", query: "mix", frequency: "weekly").id
      refs[:portfolio] = PortfolioItem.create!(user: owner, kind: "audio", title: "Sample #{actor}", url: "https://example.com/#{actor}.mp3", visibility: "public").id
      refs[:notification] = Notification.create!(user: owner, kind: "system", title: "Hello #{actor}", body: "Body").id
      refs[:availability] = AvailabilityWindow.create!(user: owner, start_at: 2.days.from_now, end_at: 3.days.from_now, status: "available", city: "Mumbai").id
      act = Act.create!(owner:, name: "Act #{actor}", act_type: "band", status: "active", currency: "INR", fee_basis: "event", city: "Mumbai", genres: ["Jazz"])
      act.act_members.create!(user: owner, display_name: owner.name, role_name: "Leader", is_leader: true, member_status: "confirmed")
      refs[:act] = act.id
      refs[:act_member] = act.act_members.create!(display_name: "Session Drummer", role_name: "Drums", is_leader: false, member_status: "confirmed").id
      refs[:inactive_act] = Act.create!(owner:, name: "Hidden act #{actor}", act_type: "duo", status: "inactive", currency: "INR", fee_basis: "event").id
      refs[:urgent] = UrgentRequest.create!(requester: owner, title: "Urgent #{actor}", role_name: "Drummer", city: "Mumbai", start_at: 1.day.from_now, currency: "INR", status: "open").id
      folder = TalentFolder.create!(owner:, name: "Folder #{actor}")
      refs[:folder] = folder.id
      project = BandProject.create!(owner:, name: "Project #{actor}", status: "open", commitment_type: "project")
      refs[:project] = project.id
      refs[:project_role] = project.band_project_roles.create!(role_name: "Bassist", status: "open", count_needed: 1, skill_level: "professional").id
      plan = CrewPlan.create!(owner:, title: "Plan #{actor}", event_type: "wedding", city: "Mumbai", currency: "INR", needs: ["sound"])
      plan.crew_plan_roles.create!(category: "Audio", role_name: "FOH Engineer", priority: "required", count_needed: 1)
      refs[:plan] = plan.id
      org = Organization.create!(owner:, name: "Org #{actor}", status: "active")
      org.organization_members.create!(user: owner, role: "owner")
      refs[:org] = org.id
    end

    # Cross-role relationships: js <-> emp and js2 <-> emp2 (peer pairs never touch each other).
    [%i[js emp], %i[js2 emp2]].each do |candidate_key, employer_key|
      candidate = u[candidate_key]
      employer = u[employer_key]
      employer_job = Job.find(world.refs[employer_key][:job])
      application = Application.create!(job: employer_job, candidate:, cover_letter: "Hi", status: "Applied")
      world.refs[candidate_key][:my_application] = application.id
      world.refs[employer_key][:received_application] = application.id
      world.refs[candidate_key][:other_job] = employer_job.id
      SavedJob.create!(user: candidate, job: employer_job)
      conversation = Conversation.create!(candidate:, employer:, job: employer_job)
      conversation.messages.create!(sender: candidate, body: "Hello from #{candidate.name}")
      world.refs[candidate_key][:conversation] = conversation.id
      world.refs[employer_key][:conversation] = conversation.id
      Organization.find(world.refs[employer_key][:org]).organization_members.create!(user: candidate, role: "member")
      world.refs[employer_key][:org_member] = candidate.id
      Organization.find(world.refs[candidate_key][:org]).organization_members.create!(user: employer, role: "member")
      world.refs[candidate_key][:org_member] = employer.id
      TalentFolder.find(world.refs[employer_key][:folder]).talent_folder_members.create!(candidate:, note: "Great")
      world.refs[candidate_key][:others_urgent] = world.refs[employer_key][:urgent]
      world.refs[employer_key][:others_urgent] = world.refs[candidate_key][:urgent]

      # Employer requests the candidate's act and vice versa, each with a quote and a created deposit.
      [[employer, candidate_key, employer_key], [candidate, employer_key, candidate_key]].each do |requester, owner_key, requester_key|
        booking = BookingRequest.create!(act_id: world.refs[owner_key][:act], requester:, event_type: "wedding", city: "Mumbai",
          currency: "INR", status: "requested", event_date: 30.days.from_now)
        quote = booking.booking_quotes.create!(created_by: u[owner_key], performance_fee: 1000, currency: "INR", status: "sent", deposit_percent: 50)
        payment = booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", amount: 500, currency: "INR", provider: "internal", status: "created")
        world.refs[owner_key][:owned_booking] = booking.id
        world.refs[requester_key][:requested_booking] = booking.id
        world.refs[requester_key][:payment] = payment.id
      end
    end

    # Talent a given actor may look at (never themselves).
    world.refs[:js][:talent] = u[:js2].id
    world.refs[:js2][:talent] = u[:js].id
    world.refs[:emp][:talent] = u[:js].id
    world.refs[:emp2][:talent] = u[:js2].id
    %i[js js2 emp emp2].each { |actor| world.refs[actor][:employer] = u[actor.to_s.start_with?("js") ? :emp : :emp2].id }

    admin = u[:admin]
    review = Review.create!(author: u[:js], employer: u[:emp], rating: 4, body: "Solid engagement", status: "published")
    world.refs[:shared].merge!(
      job: world.refs[:emp][:job], draft_job: world.refs[:emp][:draft_job], act: world.refs[:js][:act],
      inactive_act: world.refs[:js][:inactive_act], talent: u[:js].id, hidden_talent: hidden.id, employer: u[:emp].id,
      conversation: world.refs[:js][:conversation], owned_booking: world.refs[:js][:owned_booking],
      requested_booking: world.refs[:js][:requested_booking], payment: world.refs[:js][:payment],
      org: world.refs[:js][:org], org_member: world.refs[:js][:org_member], folder: world.refs[:emp][:folder],
      project: world.refs[:emp][:project], project_role: world.refs[:emp][:project_role], plan: world.refs[:emp][:plan],
      urgent: world.refs[:emp][:urgent], others_urgent: world.refs[:emp][:urgent], alert: world.refs[:js][:alert],
      portfolio: world.refs[:js][:portfolio], notification: world.refs[:js][:notification],
      availability: world.refs[:js][:availability], act_member: world.refs[:js][:act_member],
      my_application: world.refs[:js][:my_application], received_application: world.refs[:emp][:received_application],
      other_job: world.refs[:emp][:job], self: admin.id,
      user: u[:js].id, review: review.id,
      verification: VerificationRequest.create!(user: u[:js], kind: "professional", status: "pending").id,
      report: Report.create!(reporter: u[:js], entity_type: "job", entity_id: world.refs[:emp][:job], reason: "spam", status: "open").id,
      billing_attempt: BillingAttempt.create!(user: u[:emp], operation: "subscription_create", provider: "razorpay",
        idempotency_key: "matrix-#{SecureRandom.hex(4)}", state: "pending").id
    )
    world.refs[:admin][:notification] = Notification.create!(user: admin, kind: "system", title: "Admin note", body: "x").id
    CareerResource.create!(title: "Rider basics", category: "live", status: "published", description: "How to write a rider")
    world
  end

  def create_job(owner, status)
    Job.create!(employer: owner, title: "Matrix #{status} role for #{owner.name}", company: owner.profile&.company_name || owner.name,
      location: "Mumbai", kind: "Contract", opportunity_kind: "gig", workplace: "onsite", genre: "Live", skills: ["Mixing"],
      description: "A clearly documented paid engagement with rehearsals, written terms and on-site production support.",
      status:, published_at: status == "published" ? Time.current : nil)
  end

  # Counts application SQL statements (schema/transaction noise excluded) executed in the block.
  def count_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end

# Assertions shared by the matrix suites.
module ApiMatrixAssertions
  def assert_no_server_error(label)
    assert_operator response.status, :<, 500, "#{label} returned #{response.status}: #{response.body.first(400)}"
  end

  # Every error response is JSON with a human-readable `error` string (and optional `code`).
  def assert_error_shape(label)
    return if response.status < 400
    body = parsed_json(label)
    assert_kind_of Hash, body, "#{label} error body is not an object: #{response.body.first(200)}"
    assert_kind_of String, body["error"], "#{label} error body lacks an `error` string: #{response.body.first(200)}"
    assert body["code"].nil? || body["code"].is_a?(String), "#{label} error code must be a string"
    assert_nil body["traces"], "#{label} leaked a stack trace"
  end

  def parsed_json(label)
    JSON.parse(response.body)
  rescue JSON::ParserError
    flunk "#{label} returned non-JSON (#{response.media_type}): #{response.body.first(200)}"
  end

  def assert_keys(payload, keys, label)
    assert_kind_of Hash, payload, "#{label}: expected an object"
    missing = keys.map(&:to_s).reject { payload.key?(_1) }
    assert_empty missing, "#{label}: response is missing #{missing.join(', ')} (has #{payload.keys.sort.join(', ')})"
  end
end
