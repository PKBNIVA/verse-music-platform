require "test_helper"

class PublicSyntheticVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @qa = user("QA Owner", "qa-owner-visibility@example.com", "local-qa")
    @demo = user("Demo Owner", "demo-owner-visibility@example.com", "demo-20260926-1200")
    @real = user("Real Owner", "real-owner-visibility@example.com", nil)
    @acts = [@qa, @demo, @real].to_h { [_1, Act.create!(owner: _1, name: "#{_1.name} Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")] }
    @jobs = [@qa, @demo, @real].to_h do |owner|
      [owner, Job.create!(employer: owner, title: "#{owner.name} Drummer", company: owner.name, location: "Pune", kind: "Contract", genre: "Pop",
                          description: "A paid drummer engagement with clear terms, a fixed schedule and agreed fees.", status: "published", published_at: Time.current)]
    end
  end

  test "anonymous visitors do not see non-demo synthetic acts or jobs" do
    get "/api/public/acts"
    assert_equal ["Demo Owner Act", "Real Owner Act"], response.parsed_body["acts"].pluck("name").sort
    get "/api/public/acts/#{@acts[@qa].id}"
    assert_response :not_found
    get "/api/public/acts/#{@acts[@demo].id}"
    assert_response :success

    get "/api/jobs"
    assert_equal [@jobs[@demo].id, @jobs[@real].id].sort, response.parsed_body["jobs"].pluck("id").sort
    get "/api/jobs/#{@jobs[@qa].id}"
    assert_response :not_found
    get "/api/jobs/#{@jobs[@real].id}"
    assert_response :success
  end

  test "synthetic viewers still see their batch" do
    viewer = user("QA Viewer", "qa-viewer-visibility@example.com", "local-qa", "jobseeker")
    headers = { "Authorization" => "Bearer #{session_for(viewer)}" }
    get "/api/public/acts", headers: headers
    assert_includes response.parsed_body["acts"].pluck("name"), "QA Owner Act"
    get "/api/jobs/#{@jobs[@qa].id}", headers: headers
    assert_response :success
    get "/api/jobs", headers: headers
    assert_includes response.parsed_body["jobs"].pluck("id"), @jobs[@qa].id
  end

  private

  def user(name, email, batch, role = "employer")
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", synthetic_batch: batch).tap { _1.create_profile!(company_name: name) }
  end

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
