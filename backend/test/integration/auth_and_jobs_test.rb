require "test_helper"

class AuthAndJobsTest < ActionDispatch::IntegrationTest
  test "public registration cannot create an administrator" do
    post "/api/auth/register", params: {
      name: "Unexpected Admin",
      email: "unexpected-admin@example.com",
      password: "StrongPass123!",
      role: "admin"
    }, as: :json

    assert_response :unprocessable_entity
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

  test "urgent request filters apply to city and role" do
    token = register("Urgent Buyer", "urgent-buyer@example.com", "employer")
    requester = User.find_by!(email: "urgent-buyer@example.com")
    UrgentRequest.create!(requester:, title: "Jazz drummer needed", role_name: "Drummer", city: "Mumbai", currency: "INR", status: "open", start_at: 2.days.from_now)
    UrgentRequest.create!(requester:, title: "FOH needed", role_name: "FOH Engineer", city: "Delhi", currency: "INR", status: "open", start_at: 2.days.from_now)

    get "/api/urgent-requests", params: { city: "Mumbai", role: "drum" }, headers: auth(token)

    assert_response :success
    assert_equal ["Jazz drummer needed"], response.parsed_body.fetch("requests").pluck("title")
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

  test "health reports postgres-backed service" do
    get "/api/health"
    assert_response :success
    assert_equal "verse-rails", response.parsed_body["service"]
  end

  test "user supplied links reject unsafe URL schemes" do
    token = register("Safe Link User", "safe-links@example.com", "jobseeker")

    post "/api/portfolio", params: {
      type: "audio",
      title: "Unsafe sample",
      url: "javascript:alert(document.domain)"
    }, headers: auth(token), as: :json

    assert_response :unprocessable_entity
    assert_match(/HTTP or HTTPS URL/, response.parsed_body.fetch("error"))

    post "/api/verification-requests", params: {
      kind: "identity",
      evidenceUrl: "data:text/html,<script>alert(1)</script>"
    }, headers: auth(token), as: :json

    assert_response :unprocessable_entity
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

    post "/api/bookings/#{booking_id}/quote", params: { performanceFee: 60_000, depositPercent: 50 }, headers: auth(artist_token), as: :json
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

    post "/api/bookings/#{booking_id}/quote", params: { performanceFee: 70_000 }, headers: auth(artist_token), as: :json
    assert_response :conflict
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
end
