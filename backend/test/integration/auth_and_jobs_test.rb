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
end
