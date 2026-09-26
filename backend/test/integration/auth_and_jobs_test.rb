require "test_helper"

class AuthAndJobsTest < ActionDispatch::IntegrationTest
  test "public registration cannot create an administrator" do
    post "/api/auth/register", params: {
      name: "Unexpected Admin",
      email: "unexpected-admin@example.com",
      password: "StrongPass123!",
      role: "admin"
    }, as: :json

    assert_response :unprocessable_content
    assert_equal "INVALID_ROLE", response.parsed_body["code"]
    assert_not User.exists?(email: "unexpected-admin@example.com")
  end

  test "candidate registration creates a bearer-only session" do
    post "/api/auth/register", params: { name: "QA Candidate", email: "qa@example.com", password: "StrongPass123!", role: "jobseeker" }, as: :json
    assert_response :created
    assert_equal "qa@example.com", response.parsed_body.dig("user", "email")
    assert response.parsed_body["verificationRequired"]
    assert_equal 1, User.find_by!(email: "qa@example.com").email_tokens.where(purpose: "verify_email").count
    token = response.parsed_body.fetch("accessToken")

    get "/api/me"
    assert_response :unauthorized
    get "/api/me", headers: auth(token)
    assert_response :success
  end

  test "forgot password response does not reveal whether an account exists" do
    User.create!(name: "Known User", email: "known@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")

    post "/api/auth/forgot-password", params: { email: "known@example.com" }, as: :json
    known_response = response.parsed_body
    assert_response :success

    post "/api/auth/forgot-password", params: { email: "missing@example.com" }, as: :json
    assert_response :success
    assert_equal known_response, response.parsed_body
  end

  test "email verification rotates tokens and verifies only the latest link" do
    token = register("Verify Me", "verify-me@example.com", "jobseeker")

    post "/api/auth/request-email-verification", params: {}, headers: auth(token), as: :json
    assert_response :success
    first_link = response.parsed_body.fetch("debugLink")
    first_token = Rack::Utils.parse_query(URI.parse(first_link).query).fetch("token")

    post "/api/auth/request-email-verification", params: {}, headers: auth(token), as: :json
    assert_response :success
    second_link = response.parsed_body.fetch("debugLink")
    second_token = Rack::Utils.parse_query(URI.parse(second_link).query).fetch("token")

    post "/api/auth/verify-email", params: { token: first_token }, as: :json
    assert_response :bad_request
    post "/api/auth/verify-email", params: { token: second_token }, as: :json
    assert_response :success
    assert User.find_by!(email: "verify-me@example.com").email_verified?
  end

  test "taxonomy contains the music data required by creator workflows" do
    get "/api/taxonomy"

    assert_response :success
    assert_includes response.parsed_body.fetch("actTypes"), "band"
    assert_includes response.parsed_body.dig("roleCategories", "live"), "Show Runner"
    assert_includes response.parsed_body.dig("roleCategories", "writing"), "Composer"
  end

  test "global search returns normalized jobs talent acts and samples" do
    owner = User.create!(name: "Jazz Studio", email: "jazz-studio@example.com", password: "StrongPass123!", role: "employer", status: "active", profile_complete: true)
    owner.create_profile!(company_name: "Jazz Studio")
    artist = User.create!(name: "Jazz Artist", email: "jazz-artist@example.com", password: "StrongPass123!", role: "jobseeker", status: "active", profile_complete: true)
    artist.create_profile!(headline: "Jazz Vocalist", bio: "Jazz performer", skills: ["Jazz"])
    Job.create!(employer: owner, title: "Jazz Singer", company: "Jazz Studio", location: "Mumbai", kind: "Contract", genre: "Jazz", description: "A professional jazz performance opportunity with rehearsals, written terms and an experienced live production team.", status: "published")
    Act.create!(owner: artist, name: "Jazz Collective", act_type: "band", currency: "INR", fee_basis: "event", status: "active", tagline: "Modern jazz ensemble")
    PortfolioItem.create!(user: artist, kind: "audio", title: "Jazz Demo", url: "https://example.com/jazz", description: "Live jazz performance", visibility: "public")

    get "/api/search", params: { q: "jazz" }

    assert_response :success
    assert_equal "postgresql", response.parsed_body.fetch("provider")
    results = response.parsed_body.fetch("results")
    assert_equal %w[acts jobs samples talent], results.pluck("type").uniq.sort
    results.each do |result|
      assert result["url"].start_with?("/")
      assert result["title"].present?
      assert_kind_of Array, result["tags"]
    end
  end

  test "notifications include an unread count" do
    token = register("Notification User", "notifications@example.com", "jobseeker")
    user = User.find_by!(email: "notifications@example.com")
    user.notifications.create!(kind: "test", title: "Unread")
    user.notifications.create!(kind: "test", title: "Read", read_at: Time.current)

    get "/api/notifications", headers: auth(token)

    assert_response :success
    assert_equal 1, response.parsed_body.fetch("unread")
    assert_equal 2, response.parsed_body.fetch("notifications").length
  end

  test "notification unread endpoint returns only the authenticated count" do
    user = User.create!(name: "Unread User", email: "unread@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    token = session_for(user)
    user.notifications.create!(kind: "test", title: "Unread one")
    user.notifications.create!(kind: "test", title: "Unread two")
    user.notifications.create!(kind: "test", title: "Already read", read_at: Time.current)

    get "/api/notifications/unread", headers: auth(token)

    assert_response :success
    assert_equal({ "unread" => 2, "unreadMessages" => 0 }, response.parsed_body)

    get "/api/notifications/unread"
    assert_response :unauthorized
  end

  test "urgent request filters apply to city and role" do
    token = register("Urgent Buyer", "urgent-buyer@example.com", "employer")
    requester = User.find_by!(email: "urgent-buyer@example.com")
    UrgentRequest.create!(requester:, title: "Jazz drummer needed", role_name: "Drummer", city: "Mumbai", currency: "INR", status: "open", start_at: 2.days.from_now)
    UrgentRequest.create!(requester:, title: "FOH needed", role_name: "FOH Engineer", city: "Delhi", currency: "INR", status: "open", start_at: 2.days.from_now)

    get "/api/urgent-requests", params: { city: "Mumbai", role: "drum" }, headers: auth(token)

    assert_response :success
    assert_equal ["Jazz drummer needed"], response.parsed_body.fetch("requests").pluck("title")
  end

  test "urgent request owner can inspect responses and close the request" do
    owner_token = register("Urgent Owner", "urgent-owner@example.com", "employer")
    responder_token = register("Urgent Responder", "urgent-responder@example.com", "jobseeker")
    owner = User.find_by!(email: "urgent-owner@example.com")
    request = UrgentRequest.create!(requester: owner, title: "Emergency drummer", role_name: "Drummer", city: "Mumbai", currency: "INR", status: "open", start_at: 2.days.from_now)

    post "/api/urgent-requests/#{request.id}/respond", params: { message: "Available", rate: 5_000 }, headers: auth(responder_token), as: :json
    assert_response :created
    get "/api/urgent-requests/#{request.id}/responses", headers: auth(owner_token)
    assert_response :success
    assert_equal ["Urgent Responder"], response.parsed_body.fetch("responses").pluck("name")

    patch "/api/urgent-requests/#{request.id}", params: { status: "filled" }, headers: auth(owner_token), as: :json
    assert_response :success
    get "/api/urgent-requests", headers: auth(owner_token)
    assert_response :success
    owned = response.parsed_body.fetch("requests").find { _1["id"] == request.id }
    assert_equal "filled", owned.fetch("status")
    assert_equal 1, owned.fetch("responseCount")
  end

  test "employer directory never exposes contact details" do
    token = register("Directory Viewer", "viewer@example.com", "jobseeker")
    employer = User.create!(name: "Private Employer", email: "private-employer@example.com", password: "StrongPass123!", role: "employer", status: "active", profile_complete: true)
    employer.create_profile!(company_name: "Private Studio", phone: "+91 9999999999", location: "Mumbai")

    get "/api/employers", headers: auth(token)

    assert_response :success
    entry = response.parsed_body.fetch("employers").find { _1["id"] == employer.id }
    assert_equal "Private Studio", entry.fetch("companyName")
    assert_not entry.key?("email")
    assert_not entry.key?("phone")
  end

  test "conversation creation enforces opportunity ownership and applicant relationship" do
    employer_token = register("Conversation Employer", "conversation-employer@example.com", "employer")
    candidate_token = register("Conversation Candidate", "conversation-candidate@example.com", "jobseeker")
    outsider_token = register("Conversation Outsider", "conversation-outsider@example.com", "jobseeker")
    employer = User.find_by!(email: "conversation-employer@example.com")
    candidate = User.find_by!(email: "conversation-candidate@example.com")
    outsider = User.find_by!(email: "conversation-outsider@example.com")
    job = Job.create!(employer:, title: "Conversation Job", company: "Conversation Employer", location: "Mumbai", kind: "Contract", genre: "Pop", description: "A properly documented professional opportunity with clear responsibilities, written terms and collaborative production support.", status: "published")

    post "/api/conversations", params: { candidateId: outsider.id, jobId: job.id }, headers: auth(employer_token), as: :json
    assert_response :forbidden

    application = job.applications.create!(candidate:, status: "Applied")
    post "/api/conversations", params: { candidateId: candidate.id, jobId: job.id }, headers: auth(employer_token), as: :json
    assert_response :created
    conversation = Conversation.find(response.parsed_body.fetch("id"))
    assert_equal [candidate.id, employer.id, job.id], [conversation.candidate_id, conversation.employer_id, conversation.job_id]

    admin = User.create!(name: "Conversation Admin", email: "conversation-admin@example.com", password: "StrongPass123!", role: "admin", status: "active")
    post "/api/conversations", params: { employerId: admin.id }, headers: auth(outsider_token), as: :json
    assert_response :forbidden
    assert application.persisted?
    assert candidate_token.present?
  end

  test "liveness reports the running process without dependency diagnostics" do
    get "/api/live"
    assert_response :success
    assert_equal true, response.parsed_body["ok"]
    assert_equal "verse-rails", response.parsed_body["service"]
    assert response.parsed_body["release"].present?
    assert response.parsed_body["time"].present?
    assert_not response.parsed_body.key?("checks")

    get "/api/health"
    assert_response :success
    assert_equal "verse-rails", response.parsed_body["service"]
  end

  test "public readiness is minimal and does not expose deployment configuration" do
    get "/api/readiness"

    assert_response :service_unavailable
    body = response.parsed_body
    assert_equal false, body["ok"]
    assert_equal "verse-rails", body["service"]
    assert_not body.key?("checks")
    assert_not body.key?("environment")
    assert_not body.key?("integrationsReady")
  end

  test "detailed readiness diagnostics require an administrator" do
    get "/api/admin/health"
    assert_response :unauthorized

    user = User.create!(name: "Health Viewer", email: "health-viewer@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    get "/api/admin/health", headers: auth(session_for(user))
    assert_response :forbidden

    admin = User.create!(name: "Health Admin", email: "health-admin@example.com", password: "StrongPass123!", role: "admin", status: "active")
    get "/api/admin/health", headers: auth(session_for(admin))
    assert_response :service_unavailable
    body = response.parsed_body
    assert_equal true, body.dig("checks", "database", "ok")
    assert_equal true, body.dig("checks", "database", "required")
    assert_equal "test", body.dig("checks", "backgroundJobs", "adapter")
    assert_equal false, body.dig("checks", "backgroundJobs", "required")
    assert_equal true, body.dig("checks", "backgroundJobs", "schemaReady")
    assert_equal false, body.dig("checks", "payments", "required")
    assert_equal true, body["optionalIntegrationsReady"]
  end

  test "user supplied links reject unsafe URL schemes" do
    token = register("Safe Link User", "safe-links@example.com", "jobseeker")

    post "/api/portfolio", params: {
      type: "audio",
      title: "Unsafe sample",
      url: "javascript:alert(document.domain)"
    }, headers: auth(token), as: :json

    assert_response :unprocessable_content
    assert_match(/HTTP or HTTPS URL/, response.parsed_body.fetch("error"))

    post "/api/verification-requests", params: {
      kind: "professional",
      evidenceUrl: "data:text/html,<script>alert(1)</script>"
    }, headers: auth(token), as: :json

    assert_response :unprocessable_content
    assert_match(/HTTP or HTTPS URL/, response.parsed_body.fetch("error"))
  end

  test "bearer-authenticated hiring flow works from posting through shortlist" do
    employer_token = register("Hiring Studio", "studio@example.com", "employer")
    candidate_token = register("Working Artist", "artist@example.com", "jobseeker")
    User.create!(name: "Verse Admin", email: "admin@example.com", password: "StrongPass123!", role: "admin", status: "active").create_profile!
    admin_token = login("admin@example.com")

    post "/api/jobs", params: {
      title: "Touring Guitarist", location: "Mumbai", opportunityKind: "tour", workplace: "onsite",
      description: "Join a professionally managed national tour with rehearsals, written terms, travel and accommodation included.",
      compensationMin: 30_000, compensationMax: 45_000, skills: ["Guitar", "Sight-reading"]
    }, headers: auth(employer_token), as: :json
    assert_response :created
    job_id = response.parsed_body.fetch("id")

    patch "/api/admin/jobs/#{job_id}", params: { status: "published" }, headers: auth(admin_token), as: :json
    assert_response :success

    post "/api/jobs/#{job_id}/apply", params: { coverLetter: "Available for the full tour." }, headers: auth(candidate_token), as: :json
    assert_response :created
    application_id = response.parsed_body.fetch("id")

    patch "/api/employer/applications/#{application_id}", params: { status: "Shortlisted", recruiterRating: 5 }, headers: auth(employer_token), as: :json
    assert_response :success
    assert_equal "Shortlisted", Application.find(application_id).status
    assert_equal %w[created status_changed], Application.find(application_id).application_events.order(:created_at).pluck(:event_type)

    employer = User.find_by!(email: "studio@example.com")
    post "/api/reviews", params: { employerId: employer.id, rating: 5, body: "A professional engagement." }, headers: auth(candidate_token), as: :json
    assert_response :forbidden
    patch "/api/employer/applications/#{application_id}", params: { status: "Interview Scheduled", interviewDate: 2.days.from_now }, headers: auth(employer_token), as: :json
    assert_response :success
    patch "/api/employer/applications/#{application_id}", params: { status: "Offer" }, headers: auth(employer_token), as: :json
    assert_response :success
    patch "/api/employer/applications/#{application_id}", params: { status: "Hired" }, headers: auth(employer_token), as: :json
    assert_response :success
    post "/api/reviews", params: { employerId: employer.id, rating: 5, body: "A professional engagement." }, headers: auth(candidate_token), as: :json
    assert_response :created
  end

  test "booking enquiry quote acceptance and mock deposit are persisted" do
    artist_token = register("Live Artist", "live@example.com", "jobseeker")
    buyer_token = register("Event Buyer", "buyer@example.com", "employer")

    post "/api/acts", params: { name: "The Rails", actType: "band", city: "Delhi", lineupSize: 4, minFee: 50_000, leaderRole: "Band Leader" }, headers: auth(artist_token), as: :json
    assert_response :created
    act_id = response.parsed_body.fetch("id")

    post "/api/bookings", params: { actId: act_id, eventType: "concert", eventDate: 2.months.from_now, city: "Delhi", currency: "INR" }, headers: auth(buyer_token), as: :json
    assert_response :created
    booking_id = response.parsed_body.fetch("id")

    post "/api/bookings/#{booking_id}/quote", params: { performanceFee: 60_000, travelFee: 5_000, productionFee: 3_000, otherFee: 2_000, currency: "INR", depositPercent: 50, validUntil: 1.month.from_now, inclusions: "Performance and backline", exclusions: "Travel permits", cancellationTerms: "Deposit is non-refundable within seven days" }, headers: auth(artist_token), as: :json
    assert_response :created
    post "/api/bookings/#{booking_id}/status", params: { status: "accepted" }, headers: auth(buyer_token), as: :json
    assert_response :success
    post "/api/bookings/#{booking_id}/payment-order", params: {}, headers: auth(buyer_token), as: :json
    assert_response :success
    payment_id = response.parsed_body.dig("payment", "id")
    assert_equal "mock", response.parsed_body.dig("checkout", "mode")

    post "/api/bookings/#{booking_id}/payment-order", params: {}, headers: auth(buyer_token), as: :json
    assert_response :success
    assert_equal payment_id, response.parsed_body.dig("payment", "id")
    assert_equal 1, BookingPayment.where(booking_request_id: booking_id, kind: "deposit", status: "created").count

    post "/api/booking-payments/#{payment_id}/confirm", params: {}, headers: auth(buyer_token), as: :json
    assert_response :success
    assert_equal "paid", BookingPayment.find(payment_id).status

    get "/api/bookings/#{booking_id}/payments", headers: auth(artist_token)
    assert_response :success
    assert_equal [payment_id], response.parsed_body.fetch("payments").map { _1.fetch("id") }
    get "/api/bookings", headers: auth(buyer_token)
    quote = response.parsed_body.fetch("bookings").first.fetch("latestQuote")
    assert_equal 70_000, quote.fetch("total")
    assert_equal "Performance and backline", quote.fetch("inclusions")
    assert_equal "Travel permits", quote.fetch("exclusions")
    assert_equal "Deposit is non-refundable within seven days", quote.fetch("cancellationTerms")
    assert_equal 1, response.parsed_body.fetch("bookings").first.fetch("paymentCount")

    post "/api/bookings/#{booking_id}/quote", params: { performanceFee: 70_000 }, headers: auth(artist_token), as: :json
    assert_response :conflict
  end

  test "job alert owner can list update pause and delete alerts" do
    candidate = User.create!(name: "Alert Candidate", email: "alerts@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    token = session_for(candidate)
    post "/api/job-alerts", params: { name: "Tour work", query: "tour", location: "Mumbai", frequency: "weekly" }, headers: auth(token), as: :json
    assert_response :created
    alert_id = response.parsed_body.fetch("id")

    patch "/api/job-alerts/#{alert_id}", params: { frequency: "daily", active: false }, headers: auth(token), as: :json
    assert_response :success
    assert_equal "daily", response.parsed_body.dig("alert", "frequency")
    assert_equal false, response.parsed_body.dig("alert", "active")
    get "/api/job-alerts", headers: auth(token)
    assert_response :success
    assert_equal [alert_id], response.parsed_body.fetch("alerts").map { _1.fetch("id") }
    delete "/api/job-alerts/#{alert_id}", headers: auth(token)
    assert_response :success
    assert_not JobAlert.exists?(alert_id)
  end

  test "act owner can manage lineup and publishing status" do
    token = register("Act Owner", "act-owner@example.com", "jobseeker")
    post "/api/acts", params: { name: "Managed Act", actType: "band", city: "Mumbai", lineupSize: 2, leaderRole: "Band Leader" }, headers: auth(token), as: :json
    assert_response :created
    act_id = response.parsed_body.fetch("id")

    post "/api/acts/#{act_id}/members", params: { displayName: "Guest Player", roleName: "Guitarist", instrument: "Guitar" }, headers: auth(token), as: :json
    assert_response :created
    member_id = response.parsed_body.fetch("id")
    delete "/api/acts/#{act_id}/members/#{member_id}", headers: auth(token)
    assert_response :success

    delete "/api/acts/#{act_id}", headers: auth(token)
    assert_response :success
    assert_equal "inactive", Act.find(act_id).status
    patch "/api/acts/#{act_id}", params: { status: "active", tagline: "Back on stage" }, headers: auth(token), as: :json
    assert_response :success
    act = Act.find(act_id)
    assert_equal ["active", "Back on stage"], [act.status, act.tagline]
  end

  test "employer dashboard exposes totals used by the workspace" do
    employer_token = register("Dashboard Employer", "dashboard-employer@example.com", "employer")
    employer = User.find_by!(email: "dashboard-employer@example.com")
    Job.create!(employer:, title: "Published Role", company: employer.name, location: "Mumbai", kind: "Contract", genre: "Pop", description: "A complete professional opportunity with written terms, production support and a clear working schedule.", status: "published")
    Job.create!(employer:, title: "Draft Role", company: employer.name, location: "Delhi", kind: "Contract", genre: "Jazz", description: "A complete professional opportunity with written terms, production support and a clear working schedule.", status: "draft")

    get "/api/dashboard", headers: auth(employer_token)

    assert_response :success
    assert_equal 2, response.parsed_body.fetch("jobs")
    assert_equal 1, response.parsed_body.fetch("published")
    assert_equal 1, response.parsed_body.fetch("activeJobs")
  end

  test "availability supports the statuses offered by the workspace" do
    token = register("Calendar User", "calendar-user@example.com", "jobseeker")

    %w[hold booked].each do |status|
      post "/api/availability", params: { startAt: 2.days.from_now, endAt: 3.days.from_now, status:, city: "Mumbai" }, headers: auth(token), as: :json
      assert_response :created
    end
  end

  test "candidate comparison exposes only public available windows" do
    employer_token = register("Comparison Employer", "comparison-employer@example.com", "employer")
    first = User.create!(name: "Available Artist", email: "available-artist@example.com", password: "StrongPass123!", role: "jobseeker", status: "active", profile_complete: true)
    first.create_profile!(headline: "Singer")
    second = User.create!(name: "Second Artist", email: "second-artist@example.com", password: "StrongPass123!", role: "jobseeker", status: "active", profile_complete: true)
    second.create_profile!(headline: "Guitarist")
    AvailabilityWindow.create!(user: first, start_at: 2.days.from_now, end_at: 3.days.from_now, status: "available", city: "Mumbai", note: "Private schedule note")
    AvailabilityWindow.create!(user: first, start_at: 4.days.from_now, end_at: 5.days.from_now, status: "unavailable", city: "Delhi", note: "Private reason")

    get "/api/candidates/compare/list", params: { ids: [first.id, second.id].join(",") }, headers: auth(employer_token)

    assert_response :success
    available = response.parsed_body.fetch("professionals").find { _1["id"] == first.id }.fetch("availability")
    assert_equal 1, available.length
    assert_equal "available", available.first.fetch("status")
    assert available.first.key?("startAt")
    assert_not available.first.key?("start_at")
    assert_not available.first.key?("user_id")
    assert_not available.first.key?("note")
  end

  test "application pipeline rejects backward and terminal status changes" do
    employer = User.create!(name: "Pipeline Employer", email: "pipeline-employer@example.com", password: "StrongPass123!", role: "employer", status: "active")
    candidate = User.create!(name: "Pipeline Candidate", email: "pipeline-candidate@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    job = Job.create!(employer:, title: "Touring Singer", company: "Pipeline Employer", location: "Mumbai", kind: "Contract", genre: "Live", description: "A professional touring role with rehearsals, written terms and an experienced live production team.", status: "published")
    application = Application.create!(job:, candidate:, status: "Applied")
    token = login(employer.email)

    patch "/api/employer/applications/#{application.id}", params: { status: "Shortlisted" }, headers: auth(token), as: :json
    assert_response :success

    patch "/api/employer/applications/#{application.id}", params: { status: "Under Review" }, headers: auth(token), as: :json
    assert_response :conflict
    assert_equal "Shortlisted", application.reload.status

    patch "/api/employer/applications/#{application.id}", params: { status: "Interview Scheduled" }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    patch "/api/employer/applications/#{application.id}", params: { status: "Interview Scheduled", interviewDate: 2.days.from_now }, headers: auth(token), as: :json
    assert_response :success

    patch "/api/employer/applications/#{application.id}", params: { status: "Offer" }, headers: auth(token), as: :json
    assert_response :success
    patch "/api/employer/applications/#{application.id}", params: { status: "Hired" }, headers: auth(token), as: :json
    assert_response :success

    patch "/api/employer/applications/#{application.id}", params: { status: "Rejected" }, headers: auth(token), as: :json
    assert_response :conflict
    assert_equal "Hired", application.reload.status
  end

  test "employers can annotate applications without changing status and receive legal next actions" do
    employer = User.create!(name: "Contract Employer", email: "contract-employer@example.com", password: "StrongPass123!", role: "employer", status: "active")
    candidate = User.create!(name: "Experienced Candidate", email: "experienced-candidate@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    candidate.create_profile!(headline: "Touring vocalist", experience: "8 years of touring and studio work", location: "Mumbai", skills: ["Vocals"])
    job = Job.create!(employer:, title: "Lead Vocalist", company: "Contract Employer", location: "Mumbai", kind: "Contract", genre: "Live", description: "A professional lead vocalist role with rehearsals, written terms and an experienced production team.", status: "published")
    application = Application.create!(job:, candidate:, status: "Applied")
    token = login(employer.email)

    get "/api/employer/applications", headers: auth(token)
    assert_response :success
    row = response.parsed_body.fetch("applications").first
    assert_equal "8 years of touring and studio work", row.fetch("experience")
    assert_equal ["Under Review", "Shortlisted", "Rejected"], row.fetch("allowedNextStatuses")

    notification_count = Notification.where(user: candidate, kind: "application_status").count
    patch "/api/employer/applications/#{application.id}", params: { recruiterNote: "Strong live reel", recruiterRating: 5 }, headers: auth(token), as: :json
    assert_response :success
    assert_equal "Applied", application.reload.status
    assert_equal "Strong live reel", application.recruiter_note
    assert_equal 5, application.recruiter_rating
    assert_equal "recruiter_annotation", application.application_events.order(:created_at).last.event_type
    assert_equal notification_count, Notification.where(user: candidate, kind: "application_status").count

    patch "/api/employer/applications/#{application.id}", params: { recruiterRating: 6 }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_equal 5, application.reload.recruiter_rating
  end

  test "draft acts are owner-only and public act data excludes private fields" do
    owner = User.create!(name: "Private Act Owner", email: "private-act-owner@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    owner.create_profile!
    outsider = User.create!(name: "Act Browser", email: "act-browser@example.com", password: "StrongPass123!", role: "employer", status: "active")
    outsider.create_profile!
    outsider_token = session_for(outsider)
    draft = Act.create!(owner:, name: "Unannounced Act", act_type: "band", status: "draft", currency: "INR", fee_basis: "event", tech_rider_url: "https://example.com/private-tech.pdf", hospitality_rider_url: "https://example.com/private-hospitality.pdf")
    draft.act_members.create!(user: owner, display_name: owner.name, role_name: "Leader", is_leader: true, member_status: "confirmed")

    get "/api/acts/#{draft.id}", headers: auth(outsider_token)
    assert_response :not_found

    get "/api/acts/#{draft.id}", headers: auth(session_for(owner))
    assert_response :success
    assert_equal owner.id, response.parsed_body.dig("act", "owner_id")

    draft.update!(status: "active")
    get "/api/public/acts/#{draft.id}"
    assert_response :success
    public_act = response.parsed_body.fetch("act")
    assert_not public_act.key?("owner_id")
    assert_not public_act.key?("tech_rider_url")
    assert_not public_act.key?("hospitality_rider_url")
    assert_not public_act.fetch("members").first.key?("userId")
  end

  test "workspace index returns owned and joined organizations without duplicates" do
    owner = User.create!(name: "Workspace Owner", email: "workspace-owner@example.com", password: "StrongPass123!", role: "employer", status: "active")
    member = User.create!(name: "Workspace Member", email: "workspace-member@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    owned = Organization.create!(owner:, name: "Owned Studio", status: "active")
    joined = Organization.create!(owner: member, name: "Joined Studio", status: "active")
    owned.organization_members.create!(user: owner, role: "owner")
    joined.organization_members.create!(user: member, role: "owner")
    joined.organization_members.create!(user: owner, role: "member")

    get "/api/organizations", headers: auth(session_for(owner))

    assert_response :success
    organizations = response.parsed_body.fetch("organizations")
    assert_equal [joined.id, owned.id].sort, organizations.pluck("id").sort
    assert_equal organizations.pluck("id").uniq, organizations.pluck("id")
  end

  private

  def register(name, email, role)
    post "/api/auth/register", params: { name:, email:, password: "StrongPass123!", role: }, as: :json
    assert_response :created
    response.parsed_body.fetch("accessToken")
  end

  def login(email)
    post "/api/auth/login", params: { email:, password: "StrongPass123!" }, as: :json
    assert_response :success
    response.parsed_body.fetch("accessToken")
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
