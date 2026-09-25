require "test_helper"

class SyntheticTwoSidedJourneyTest < ActionDispatch::IntegrationTest
  BATCH = "journey-test-batch"
  PASSWORD = "SyntheticPass123!"

  setup do
    SyntheticQa::BatchCleanup.call(batch: BATCH)
    SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 8, employers: 3, password: PASSWORD)
  end

  teardown { SyntheticQa::BatchCleanup.call(batch: BATCH) }

  test "professional and employer complete discovery application messaging booking payment and workspace flows" do
    candidate = User.synthetic(BATCH).jobseeker.first
    candidate_token = login(candidate.email)
    other_job = Job.where(employer_id: User.synthetic(BATCH).employer.select(:id)).where.not(id: candidate.applications.select(:job_id)).first!
    employer = other_job.employer
    employer_token = login(employer.email)

    get "/api/jobs?q=QA"
    assert_response :success
    assert_includes response.parsed_body.fetch("jobs").map { _1.fetch("id") }, other_job.id

    post "/api/saved-jobs/#{other_job.id}", headers: auth(candidate_token)
    assert_response :created
    post "/api/jobs/#{other_job.id}/apply", params: { coverLetter: "Synthetic end-to-end application", screeningAnswers: ["QA credit"] }, as: :json, headers: auth(candidate_token)
    assert_response :created
    application_id = response.parsed_body.fetch("id")

    get "/api/employer/applications", headers: auth(employer_token)
    assert_response :success
    assert_includes response.parsed_body.fetch("applications").map { _1.fetch("id") }, application_id
    patch "/api/employer/applications/#{application_id}", params: { status: "Under Review", recruiterRating: 4, recruiterNote: "Synthetic review" }, as: :json, headers: auth(employer_token)
    assert_response :success

    post "/api/conversations", params: { candidateId: candidate.id, jobId: other_job.id }, as: :json, headers: auth(employer_token)
    assert_response :created
    conversation_id = response.parsed_body.fetch("id")
    post "/api/conversations/#{conversation_id}/messages", params: { body: "Employer synthetic message" }, as: :json, headers: auth(employer_token)
    assert_response :created
    post "/api/conversations/#{conversation_id}/messages", params: { body: "Candidate synthetic reply" }, as: :json, headers: auth(candidate_token)
    assert_response :created
    get "/api/conversations/#{conversation_id}/messages", headers: auth(employer_token)
    assert_response :success
    assert_equal 2, response.parsed_body.fetch("messages").last(2).size

    post "/api/availability", params: { startAt: 3.months.from_now, endAt: 3.months.from_now + 5.hours, status: "available", city: "Mumbai" }, as: :json, headers: auth(candidate_token)
    assert_response :created
    get "/api/availability", headers: auth(candidate_token)
    assert_response :success
    assert_operator response.parsed_body.fetch("windows").size, :>=, 2

    get "/api/organizations", headers: auth(employer_token)
    assert response.successful?, "Workspace listing failed with #{response.status}: #{response.body}"
    organization = response.parsed_body.fetch("organizations").first
    get "/api/organizations/#{organization.fetch('id')}/members", headers: auth(employer_token)
    assert_response :success
    assert_equal employer.id, response.parsed_body.fetch("members").first.fetch("id")

    booking = BookingRequest.where(requester: employer, status: "quoted").first!
    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, as: :json, headers: auth(employer_token)
    assert_response :success
    post "/api/bookings/#{booking.id}/payment-order", params: {}, as: :json, headers: auth(employer_token)
    assert_response :success
    payment_id = response.parsed_body.fetch("payment").fetch("id")
    assert_equal "mock", response.parsed_body.dig("checkout", "mode")
    post "/api/booking-payments/#{payment_id}/confirm", params: {}, as: :json, headers: auth(employer_token)
    assert_response :success
    assert_equal "paid", BookingPayment.find(payment_id).status

    get "/api/notifications", headers: auth(candidate_token)
    assert_response :success
    assert response.parsed_body.fetch("notifications").any? { _1.fetch("kind") == "application_status" }
  end

  test "cross-role authorization and invalid state changes remain blocked" do
    candidate = User.synthetic(BATCH).jobseeker.first
    application = Application.joins(:job).where(candidate:).first!
    employer = application.job.employer
    candidate_token = login(candidate.email)
    employer_token = login(employer.email)

    patch "/api/employer/applications/#{application.id}", params: { status: "Hired" }, as: :json, headers: auth(candidate_token)
    assert_response :not_found

    booking = BookingRequest.where(requester: employer).first!
    post "/api/bookings/#{booking.id}/status", params: { status: "completed" }, as: :json, headers: auth(employer_token)
    assert_response :conflict

    conversation = Conversation.find_by!(candidate:)
    post "/api/conversations/#{conversation.id}/messages", params: { body: "   " }, as: :json, headers: auth(candidate_token)
    assert_response :unprocessable_entity
  end

  private

  def login(email)
    post "/api/auth/login", params: { email:, password: PASSWORD }, as: :json
    assert_response :success
    response.parsed_body.fetch("accessToken")
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }
end
