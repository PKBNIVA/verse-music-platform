require "test_helper"
require_relative "../synthetic_trace_assertions"

class AdminDemoDataTest < ActionDispatch::IntegrationTest
  include SyntheticTraceAssertions

  setup do
    @admin = create_user("Ops Admin", "admin")
    @jobseeker = create_user("Real Artist", "jobseeker", headline: "Playback vocalist")
    @employer = create_user("Real Studio", "employer", company_name: "Real Studio")
  end

  test "every endpoint is admin-only" do
    requests = [[:get, "/api/admin/demo-data"], [:post, "/api/admin/demo-data"], [:delete, "/api/admin/demo-data"],
      [:delete, "/api/admin/demo-data/demo-20260101-0000"], [:get, "/api/admin/demo-data/jobs/abc"]]
    requests.each do |verb, path|
      options = verb == :post ? { params: { size: "small" }, as: :json } : {}
      send(verb, path, **options)
      assert_response :unauthorized, "#{verb} #{path} without a session"
      [@jobseeker, @employer].each do |user|
        send(verb, path, **options, headers: auth(user))
        assert_response :forbidden, "#{verb} #{path} as #{user.role}"
      end
    end
    assert_no_enqueued_jobs
  end

  test "create enqueues a seed job, reports its state and audits the request" do
    get "/api/admin/demo-data", headers: auth(@admin)
    assert_response :success
    body = response.parsed_body
    assert_equal [], body.fetch("batches")
    assert_equal false, body.fetch("busy")
    assert_equal 300, body.fetch("maxUsers")
    assert_equal({ "artists" => 20, "employers" => 8 }, body.dig("sizes", "small"))

    assert_enqueued_with(job: DemoDataSeedJob) do
      post "/api/admin/demo-data", params: { size: "small" }, as: :json, headers: auth(@admin)
    end
    assert_response :accepted
    job_id = response.parsed_body.fetch("jobId")
    assert_equal "queued", response.parsed_body.dig("job", "state")
    assert_match(/\Ademo-\d{8}-\d{4}/, response.parsed_body.dig("job", "batch"))
    assert AuditLog.exists?(actor: @admin, action: "demo_data.seed")

    get "/api/admin/demo-data/jobs/#{job_id}", headers: auth(@admin)
    assert_response :success
    assert_equal "queued", response.parsed_body.dig("job", "state")
    get "/api/admin/demo-data", headers: auth(@admin)
    assert_equal true, response.parsed_body.fetch("busy")
  end

  test "refuses a second job while one is queued or running" do
    post "/api/admin/demo-data", params: { size: "small" }, as: :json, headers: auth(@admin)
    assert_response :accepted
    post "/api/admin/demo-data", params: { size: "small" }, as: :json, headers: auth(@admin)
    assert_response :conflict
    assert_equal "DEMO_JOB_RUNNING", response.parsed_body.fetch("code")
    delete "/api/admin/demo-data", headers: auth(@admin)
    assert_response :conflict
    assert_enqueued_jobs 1
  end

  test "a job that stopped reporting no longer blocks new work" do
    SyntheticQa::DemoJobs.record!("stale-job", "running", actor_id: @admin.id, kind: "seed")
    AuditLog.where(entity_id: "stale-job").update_all(created_at: 2.hours.ago)
    post "/api/admin/demo-data", params: { size: "small" }, as: :json, headers: auth(@admin)
    assert_response :accepted
    assert_equal "failed", SyntheticQa::DemoJobs.find("stale-job")[:state]
  end

  test "rejects unknown sizes, the 300 user cap and non-demo batches" do
    post "/api/admin/demo-data", params: { size: "huge" }, as: :json, headers: auth(@admin)
    assert_response :unprocessable_content

    SyntheticQa::BatchSeeder.call(batch: "demo-20260101-0000", jobseekers: 100, employers: 1)
    post "/api/admin/demo-data", params: { size: "large" }, as: :json, headers: auth(@admin)
    assert_response :unprocessable_content
    assert_equal "DEMO_CAP_EXCEEDED", response.parsed_body.fetch("code")

    delete "/api/admin/demo-data/qa-hidden-batch", headers: auth(@admin)
    assert_response :unprocessable_content
    delete "/api/admin/demo-data/demo-19990101-0000", headers: auth(@admin)
    assert_response :not_found
    assert_no_enqueued_jobs
  ensure
    SyntheticQa::BatchCleanup.call(batch: "demo-20260101-0000")
  end

  test "seed, list, public visibility with demo badges, then delete all leaves no trace" do
    hidden_user = create_user("Hidden QA Vocalist", "jobseeker", headline: "Playback vocalist")
    hidden_user.update!(synthetic_batch: "qa-hidden-batch")

    post "/api/admin/demo-data", params: { size: "small" }, as: :json, headers: auth(@admin)
    assert_response :accepted
    seed_id = response.parsed_body.fetch("jobId")
    perform_enqueued_jobs
    assert_equal "succeeded", SyntheticQa::DemoJobs.find(seed_id)[:state]

    get "/api/admin/demo-data", headers: auth(@admin)
    demo = response.parsed_body.fetch("batches").find { _1["demo"] }
    assert_equal 20, demo.fetch("artists")
    assert_equal 8, demo.fetch("employers")
    assert_equal "public", demo.fetch("visibility")
    assert_equal "hidden", response.parsed_body.fetch("batches").find { _1["name"] == "qa-hidden-batch" }.fetch("visibility")
    assert_equal "succeeded", response.parsed_body.fetch("jobs").first.fetch("state")
    batch = demo.fetch("name")
    demo_users = User.synthetic(batch)
    assert demo_users.none? { _1.authenticate("SyntheticPass123!") }

    get "/api/public/talent"
    talent = response.parsed_body.fetch("talent")
    ids = talent.pluck("id")
    assert_includes ids, @jobseeker.id
    assert_not_includes ids, hidden_user.id, "non-demo synthetic batches stay hidden"
    assert_equal 20, talent.count { _1["demo"] == true }
    assert_equal false, talent.find { _1["id"] == @jobseeker.id }.fetch("demo")
    assert talent.none? { _1.key?("synthetic_batch") || _1.key?("email") }

    demo_artist = demo_users.jobseeker.first
    get "/api/public/talent/#{demo_artist.id}"
    assert_equal true, response.parsed_body.dig("professional", "demo")

    get "/api/jobs"
    jobs = response.parsed_body.fetch("jobs")
    assert jobs.any? { _1["demo"] == true }
    get "/api/jobs/#{jobs.find { _1['demo'] }.fetch('id')}"
    assert_equal true, response.parsed_body.dig("job", "demo")

    get "/api/public/acts"
    assert response.parsed_body.fetch("acts").all? { _1["demo"] == true }
    get "/api/public/acts/#{response.parsed_body.fetch('acts').first.fetch('id')}"
    assert_equal true, response.parsed_body.dig("act", "demo")

    get "/api/search", params: { q: "Vocalist" }
    results = response.parsed_body.fetch("results")
    assert results.any? { _1["type"] == "talent" && _1["demo"] == true }
    assert_not_includes results.pluck("id"), hidden_user.id
    assert results.find { _1["id"] == @jobseeker.id }&.fetch("demo") == false

    # A real user interacts with demo content; purge removes that interaction but never the real user.
    demo_job = Job.published.find_by!(employer_id: demo_users.employer.select(:id))
    Application.create!(job: demo_job, candidate: @jobseeker, status: "Applied")
    TalentShortlist.create!(employer: @employer, candidate: demo_artist)
    user_ids = demo_users.pluck(:id)

    delete "/api/admin/demo-data", headers: auth(@admin)
    assert_response :accepted
    purge_id = response.parsed_body.fetch("jobId")
    assert_equal [batch], response.parsed_body.dig("job", "batches")
    perform_enqueued_jobs
    purge = SyntheticQa::DemoJobs.find(purge_id)
    assert_equal "succeeded", purge[:state]
    assert_equal 28, purge.dig(:result, "usersRemoved")

    assert_no_user_traces(user_ids)
    assert User.exists?(@jobseeker.id)
    assert User.exists?(@employer.id)
    assert User.exists?(hidden_user.id), "purge never touches non-demo synthetic batches"
    assert User.exists?(@admin.id)
    assert AuditLog.exists?(action: "demo_data.purge_all", actor: @admin), "the audit trail survives the purge"

    get "/api/public/talent"
    assert response.parsed_body.fetch("talent").none? { _1["demo"] }
    get "/api/jobs"
    assert response.parsed_body.fetch("jobs").none? { _1["demo"] }
    get "/api/public/acts"
    assert_empty response.parsed_body.fetch("acts")

    # Purging again is harmless.
    delete "/api/admin/demo-data", headers: auth(@admin)
    assert_response :accepted
    perform_enqueued_jobs
    get "/api/admin/demo-data", headers: auth(@admin)
    assert_equal "succeeded", response.parsed_body.fetch("jobs").first.fetch("state")
  end

  test "delete one batch only removes that batch" do
    SyntheticQa::BatchSeeder.call(batch: "demo-20260101-0001", jobseekers: 2, employers: 1)
    SyntheticQa::BatchSeeder.call(batch: "demo-20260101-0002", jobseekers: 2, employers: 1)
    delete "/api/admin/demo-data/demo-20260101-0001", headers: auth(@admin)
    assert_response :accepted
    perform_enqueued_jobs
    assert_equal 0, User.synthetic("demo-20260101-0001").count
    assert_equal 3, User.synthetic("demo-20260101-0002").count
  ensure
    SyntheticQa::BatchCleanup.call(batch: "demo-20260101-0001")
    SyntheticQa::BatchCleanup.call(batch: "demo-20260101-0002")
  end

  private

  def create_user(name, role, profile = {})
    email = "demo-test-#{SecureRandom.hex(4)}@example.com"
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", profile_complete: true).tap do |user|
      user.create_profile!(profile) unless role == "admin"
    end
  end

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end
end
