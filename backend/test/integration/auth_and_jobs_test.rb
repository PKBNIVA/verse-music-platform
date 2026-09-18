require "test_helper"

class AuthAndJobsTest < ActionDispatch::IntegrationTest
  test "candidate registration creates a secure session" do
    post "/api/auth/register", params: { name: "QA Candidate", email: "qa@example.com", password: "StrongPass123!", role: "jobseeker" }, as: :json
    assert_response :created
    assert_equal "qa@example.com", response.parsed_body.dig("user", "email")
    get "/api/me"
    assert_response :success
  end

  test "health reports postgres-backed service" do
    get "/api/health"
    assert_response :success
    assert_equal "verse-rails", response.parsed_body["service"]
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

    post "/api/booking-payments/#{payment_id}/confirm", params: {}, headers: auth(buyer_token), as: :json
    assert_response :success
    assert_equal "paid", BookingPayment.find(payment_id).status
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
