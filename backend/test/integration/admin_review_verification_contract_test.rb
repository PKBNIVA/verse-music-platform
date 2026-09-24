require "test_helper"

class AdminReviewVerificationContractTest < ActionDispatch::IntegrationTest
  test "review selector and create authorization share the completed-hire rule" do
    candidate = create_user("Review Candidate", "review-candidate-contract@example.com", "jobseeker")
    eligible = create_user("Eligible Studio", "eligible-studio-contract@example.com", "employer")
    ineligible = create_user("Ineligible Studio", "ineligible-studio-contract@example.com", "employer")
    job = Job.create!(
      employer: eligible,
      title: "Completed Session",
      company: "Eligible Studio",
      location: "Mumbai",
      kind: "Contract",
      genre: "Studio",
      description: "A completed professional studio engagement with written terms and agreed compensation.",
      status: "published"
    )
    Application.create!(job:, candidate:, status: "Hired")
    token = session_for(candidate)

    get "/api/reviews", headers: auth(token)
    assert_response :success
    employers = response.parsed_body.fetch("eligibleEmployers")
    assert_equal [eligible.id], employers.pluck("id")
    assert_equal true, employers.first.fetch("eligibleForReview")

    post "/api/reviews", params: { employerId: ineligible.id, rating: 5, body: "No completed engagement." }, headers: auth(token), as: :json
    assert_response :forbidden

    post "/api/reviews", params: { employerId: eligible.id, rating: 5, body: "A completed professional engagement." }, headers: auth(token), as: :json
    assert_response :created

    get "/api/reviews", headers: auth(token)
    assert_response :success
    assert_empty response.parsed_body.fetch("eligibleEmployers")
  end

  test "verification kind is required and bound to account type" do
    professional = create_user("Verified Artist", "verified-artist-contract@example.com", "jobseeker")
    organization = create_user("Verified Studio", "verified-studio-contract@example.com", "employer")

    post "/api/verification-requests", params: { kind: "organization", evidenceUrl: "https://example.com/artist" }, headers: auth(session_for(professional)), as: :json
    assert_response :bad_request
    assert_equal "INVALID_VERIFICATION_KIND", response.parsed_body.fetch("code")

    post "/api/verification-requests", params: { kind: "professional", evidenceUrl: "https://example.com/artist" }, headers: auth(session_for(professional)), as: :json
    assert_response :created
    assert_equal "professional", VerificationRequest.find(response.parsed_body.fetch("id")).kind

    post "/api/verification-requests", params: { kind: "organization", evidenceUrl: "https://example.com/studio" }, headers: auth(session_for(organization)), as: :json
    assert_response :created
    assert_equal "organization", VerificationRequest.find(response.parsed_body.fetch("id")).kind
  end

  test "admin responses expose frontend-compatible timestamp and reindex count" do
    admin = create_user("Contract Admin", "contract-admin-contract@example.com", "admin")
    token = session_for(admin)

    get "/api/admin/users", headers: auth(token)
    assert_response :success
    serialized_admin = response.parsed_body.fetch("users").find { _1["id"] == admin.id }
    assert serialized_admin.fetch("createdAt").present?

    post "/api/admin/search/reindex", params: {}, headers: auth(token), as: :json
    assert_response :success
    assert_equal response.parsed_body.fetch("indexed"), response.parsed_body.fetch("count")
  end

  private

  def create_user(name, email, role)
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active").tap(&:create_profile!)
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
