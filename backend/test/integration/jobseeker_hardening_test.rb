require "test_helper"

# Regressions found by the jobseeker-area crawl: inputs the UI can send that used to
# return HTTP 500 or leak employer-only data.
class JobseekerHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @seeker = User.create!(name: "Seeker One", email: "seeker-one@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    @employer = User.create!(name: "Studio Owner", email: "studio-owner@example.com", password: "StrongPass123!", role: "employer", status: "active")
    @job = Job.create!(employer: @employer, title: "Session Drummer", company: "Hardening Studio", location: "Mumbai", kind: "Contract",
      genre: "Jazz", description: "A professional session opportunity with written terms, rehearsals and a clear schedule for the band.",
      status: "published", skills: ["Drums"])
  end

  test "dashboard does not fail for a location with a blank first segment" do
    @seeker.create_profile!(location: ",", skills: ["Drums"])
    get "/api/dashboard", headers: auth(@seeker)
    assert_response :success
    fit = response.parsed_body["recommendedJobs"].first["fitScore"]
    assert_equal 35 + 12, fit, "a blank city must not count as a location match"

    @seeker.profile.update!(location: " , Mumbai")
    get "/api/dashboard", headers: auth(@seeker)
    assert_response :success
    assert_equal 35 + 12 + 10, response.parsed_body["recommendedJobs"].first["fitScore"]
  end

  test "profile rejects out-of-range, negative and non-numeric rates with 422" do
    [
      [{ yearsExperience: 99_999_999_999 }, "Years of experience is too large"],
      [{ hourlyRate: 1e20 }, "Hourly rate is too large"],
      [{ sessionRate: -5 }, "Session rate cannot be negative"],
      [{ showRate: "abc" }, "Show rate must be a number"],
      [{ currency: "XYZ" }, "Currency must be one of INR, USD, EUR, GBP"]
    ].each do |payload, message|
      put "/api/profile", params: payload, headers: auth(@seeker), as: :json
      assert_response :unprocessable_entity, payload.inspect
      assert_equal message, response.parsed_body["error"]
    end

    put "/api/profile", params: { yearsExperience: "7", hourlyRate: "", currency: "USD" }, headers: auth(@seeker), as: :json
    assert_response :success
    assert_equal 7, @seeker.reload.profile.years_experience
  end

  test "candidates never see the employer's private rating or note" do
    Application.create!(job: @job, candidate: @seeker, recruiter_rating: 2, recruiter_note: "Weak timing", status: "Under Review")
    get "/api/applications", headers: auth(@seeker)
    assert_response :success
    application = response.parsed_body["applications"].first
    assert_equal "Under Review", application["status"]
    %w[recruiter_rating recruiter_note recruiterRating recruiterNote].each { assert_not application.key?(_1), _1 }
    assert_not_includes response.body, "Weak timing"
  end

  test "job alerts explain invalid frequency and default a blank name" do
    post "/api/job-alerts", params: { name: "x", frequency: "hourly" }, headers: auth(@seeker), as: :json
    assert_response :unprocessable_entity
    assert_equal "Frequency must be daily, weekly, or saved", response.parsed_body["error"]

    post "/api/job-alerts", params: { name: "   " }, headers: auth(@seeker), as: :json
    assert_response :created
    alert = JobAlert.find(response.parsed_body["id"])
    assert_equal "Saved search", alert.name
    assert_equal "saved", alert.frequency
  end

  test "apply validates the note and keeps only text screening answers" do
    post "/api/jobs/#{@job.id}/apply", params: { coverLetter: { a: 1 } }, headers: auth(@seeker), as: :json
    assert_response :unprocessable_entity
    post "/api/jobs/#{@job.id}/apply", params: { coverLetter: "x" * 5_001 }, headers: auth(@seeker), as: :json
    assert_response :unprocessable_entity

    post "/api/jobs/#{@job.id}/apply", params: { coverLetter: "Fits my jazz work", screeningAnswers: ["Q :: A", { bad: 1 }] }, headers: auth(@seeker), as: :json
    assert_response :created
    assert_equal ["Q :: A"], Application.find(response.parsed_body["id"]).screening_answers
  end

  test "array or hash filters return 400 instead of 500" do
    ["location[]=a", "kind[x]=y", "q[]=drums", "paid[]=true"].each do |query|
      get "/api/jobs?#{query}"
      assert_response :bad_request, query
      assert_equal "INVALID_FILTER", response.parsed_body["code"]
    end
    get "/api/jobs?location=Mumbai&kind=job"
    assert_response :success
  end

  test "reviews reject a non-string employerId and rate-check input" do
    get "/api/reviews?employerId[x]=y", headers: auth(@seeker)
    assert_response :unprocessable_entity
    assert_equal "INVALID_EMPLOYER", response.parsed_body["code"]

    post "/api/reviews", params: { employerId: [@employer.id], rating: 5, body: "Great" }, headers: auth(@seeker), as: :json
    assert_response :unprocessable_entity
    assert_equal "INVALID_EMPLOYER", response.parsed_body["code"]

    get "/api/reviews?employerId=#{@employer.id}", headers: auth(@seeker)
    assert_response :success
  end

  private

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end
end
