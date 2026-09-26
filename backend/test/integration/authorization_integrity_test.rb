require "test_helper"

class AuthorizationIntegrityTest < ActionDispatch::IntegrationTest
  setup { @seq = 0 }

  test "verification request without evidence is accepted and stores no placeholder" do
    professional = create_user("Evidence Free", "jobseeker")

    post "/api/verification-requests", params: { kind: "professional" }, headers: auth(professional), as: :json
    assert_response :created
    request_record = VerificationRequest.find(response.parsed_body.fetch("id"))
    assert_nil request_record.evidence_url
    assert_equal "pending", request_record.status

    post "/api/verification-requests", params: { kind: "professional", evidenceUrl: "" }, headers: auth(professional), as: :json
    assert_response :created
    assert_nil VerificationRequest.find(response.parsed_body.fetch("id")).evidence_url

    column = VerificationRequest.columns_hash
    assert column.fetch("evidence_url").null
    assert_nil column.fetch("evidence_url").default
    assert_nil column.fetch("kind").default
    assert_equal "pending", column.fetch("status").default
  end

  test "workspace roles are whitelisted and admin grants are owner-only" do
    owner = create_user("Workspace Owner", "employer")
    Subscription.create!(user: owner, plan_code: "studio", provider: "internal", status: "active")
    org = Organization.create!(owner:, name: "Role Studio", status: "active")
    org.organization_members.create!(user: owner, role: "owner")
    admin = create_user("Workspace Admin", "employer")
    recruiter = create_user("Workspace Recruiter", "jobseeker")
    booker = create_user("Workspace Booker", "jobseeker")
    co_owner = create_user("Workspace Co Owner", "employer")
    other_admin = create_user("Workspace Other Admin", "employer")

    post "/api/organizations/#{org.id}/members", params: { email: admin.email, role: "owner" }, headers: auth(owner), as: :json
    assert_response :bad_request
    assert_equal "INVALID_ROLE", response.parsed_body["code"]
    post "/api/organizations/#{org.id}/members", params: { email: admin.email, role: "superuser" }, headers: auth(owner), as: :json
    assert_response :bad_request
    assert_not org.organization_members.exists?(user: admin)

    post "/api/organizations/#{org.id}/members", params: { email: admin.email, role: "admin" }, headers: auth(owner), as: :json
    assert_response :created
    assert_equal "admin", member_role(org, admin)

    post "/api/organizations/#{org.id}/members", params: { email: recruiter.email, role: "admin" }, headers: auth(admin), as: :json
    assert_response :forbidden
    post "/api/organizations/#{org.id}/members", params: { email: recruiter.email, role: "owner" }, headers: auth(admin), as: :json
    assert_response :bad_request
    post "/api/organizations/#{org.id}/members", params: { email: recruiter.email, role: "recruiter" }, headers: auth(admin), as: :json
    assert_response :created
    assert_equal "recruiter", member_role(org, recruiter)
    post "/api/organizations/#{org.id}/members", params: { email: booker.email }, headers: auth(admin), as: :json
    assert_response :created
    assert_equal "member", member_role(org, booker)

    # Legacy rows created before the whitelist: admins still cannot remove owners or other admins.
    org.organization_members.create!(user: co_owner, role: "owner")
    org.organization_members.create!(user: other_admin, role: "admin")
    delete "/api/organizations/#{org.id}/members/#{co_owner.id}", headers: auth(admin)
    assert_response :forbidden
    delete "/api/organizations/#{org.id}/members/#{other_admin.id}", headers: auth(admin)
    assert_response :forbidden
    delete "/api/organizations/#{org.id}/members/#{owner.id}", headers: auth(admin)
    assert_response :conflict
    delete "/api/organizations/#{org.id}/members/#{recruiter.id}", headers: auth(admin)
    assert_response :success
    assert_not org.organization_members.exists?(user: recruiter)

    delete "/api/organizations/#{org.id}/members/#{other_admin.id}", headers: auth(owner)
    assert_response :success
    delete "/api/organizations/#{org.id}/members/#{co_owner.id}", headers: auth(owner)
    assert_response :success
    delete "/api/organizations/#{org.id}/members/#{admin.id}", headers: auth(admin)
    assert_response :success, "an admin may leave the workspace"
    assert_equal [owner.id, booker.id].sort, org.organization_members.pluck(:user_id).sort

    post "/api/organizations/#{org.id}/members", params: { email: admin.email, role: "member" }, headers: auth(booker), as: :json
    assert_response :forbidden
  end

  test "act lineup only links active professionals with known statuses" do
    owner = create_user("Act Owner", "jobseeker")
    act = Act.create!(owner:, name: "Consent Band", act_type: "band", status: "active", currency: "INR", fee_basis: "event")
    professional = create_user("Linked Player", "jobseeker")
    employer = create_user("Not A Player", "employer")
    suspended = create_user("Suspended Player", "jobseeker")
    suspended.update!(status: "suspended")

    post "/api/acts/#{act.id}/members", params: { displayName: "Anyone", roleName: "Drums", memberStatus: "leader" }, headers: auth(owner), as: :json
    assert_response :bad_request
    [SecureRandom.uuid, employer.id, suspended.id].each do |user_id|
      post "/api/acts/#{act.id}/members", params: { displayName: "Anyone", roleName: "Drums", userId: user_id }, headers: auth(owner), as: :json
      assert_response :not_found
    end
    post "/api/acts/#{act.id}/members", params: { roleName: "Drums" }, headers: auth(owner), as: :json
    assert_response :unprocessable_content
    assert_equal 0, act.act_members.count

    post "/api/acts/#{act.id}/members", params: { displayName: "Session Drummer", roleName: "Drums", instrument: "Drums" }, headers: auth(owner), as: :json
    assert_response :created
    assert_equal "confirmed", ActMember.find(response.parsed_body.fetch("id")).member_status
    post "/api/acts/#{act.id}/members", params: { displayName: professional.name, roleName: "Bass", userId: professional.id, memberStatus: "confirmed" }, headers: auth(owner), as: :json
    assert_response :created
    assert_equal professional.id, ActMember.find(response.parsed_body.fetch("id")).user_id
    post "/api/acts/#{act.id}/members", params: { displayName: professional.name, roleName: "Bass", userId: professional.id }, headers: auth(owner), as: :json
    assert_response :conflict
  end

  test "talent folders only hold discoverable professionals" do
    employer = create_user("Folder Employer", "employer")
    folder = TalentFolder.create!(owner: employer, name: "Shortlist")
    visible = create_user("Visible Player", "jobseeker")
    hidden = create_user("Hidden Player", "jobseeker")
    hidden.update!(profile_complete: false)
    other_employer = create_user("Other Employer", "employer")

    [SecureRandom.uuid, hidden.id, other_employer.id].each do |candidate_id|
      post "/api/talent-folders/#{folder.id}/candidates/#{candidate_id}", params: { note: "x" }, headers: auth(employer), as: :json
      assert_response :not_found
    end
    post "/api/talent-folders/#{folder.id}/candidates/#{visible.id}", params: { note: "first" }, headers: auth(employer), as: :json
    assert_response :created
    post "/api/talent-folders/#{folder.id}/candidates/#{visible.id}", params: { note: "updated" }, headers: auth(employer), as: :json
    assert_response :created
    assert_equal ["updated"], folder.talent_folder_members.pluck(:note)

    get "/api/talent-folders/#{folder.id}", headers: auth(employer)
    assert_response :success
    assert_equal [visible.id], response.parsed_body.fetch("candidates").pluck("id")

    visible.update!(status: "suspended")
    get "/api/talent-folders/#{folder.id}", headers: auth(employer)
    assert_response :success
    assert_empty response.parsed_body.fetch("candidates")
  end

  test "conversation creation and message sending are rate limited per user" do
    # The test environment uses :null_store; rate counters need a real cache.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    employer = create_user("Chatty Employer", "employer")
    candidate = create_user("Chatty Candidate", "jobseeker")
    conversation = Conversation.create!(candidate:, employer:)
    stale = 2.days.ago
    conversation.update_columns(updated_at: stale)

    post "/api/conversations/#{conversation.id}/messages", params: { body: "Hello" }, headers: auth(employer), as: :json
    assert_response :created
    assert_operator conversation.reload.updated_at, :>, stale, "sending a message must bump the conversation"

    MessagesController::SEND_LIMIT_PER_HOUR.pred.times { Rails.cache.increment(rate_key("message", employer), 1, expires_in: 1.hour) }
    post "/api/conversations/#{conversation.id}/messages", params: { body: "Over the limit" }, headers: auth(employer), as: :json
    assert_response :too_many_requests
    assert_equal "RATE_LIMITED", response.parsed_body["code"]
    assert response.headers["Retry-After"].present?
    post "/api/conversations/#{conversation.id}/messages", params: { body: "Reply" }, headers: auth(candidate), as: :json
    assert_response :created, "limits are per sender"

    ConversationsController::CREATE_LIMIT_PER_HOUR.times do
      post "/api/conversations", params: { employerId: employer.id }, headers: auth(candidate), as: :json
      assert_response :created
    end
    post "/api/conversations", params: { employerId: employer.id }, headers: auth(candidate), as: :json
    assert_response :too_many_requests
  ensure
    Rails.cache = original_cache
  end

  test "inbox orders by latest message and message history is capped to the newest" do
    employer = create_user("Inbox Employer", "employer")
    candidate = create_user("Inbox Candidate", "jobseeker")
    older = Conversation.create!(candidate:, employer:)
    newer = Conversation.create!(candidate:, employer:, job: create_job(employer))
    older.messages.create!(sender: candidate, body: "first", created_at: 3.hours.ago)
    newer.messages.create!(sender: candidate, body: "second", created_at: 2.hours.ago)
    older.messages.create!(sender: employer, body: "latest in older", created_at: 1.hour.ago)
    newer.update_columns(updated_at: 2.hours.ago)

    get "/api/conversations", headers: auth(candidate)
    assert_response :success
    rows = response.parsed_body.fetch("conversations")
    assert_equal [older.id, newer.id], rows.pluck("id")
    assert_equal ["latest in older", "second"], rows.pluck("lastMessage")

    base = 1.day.ago
    rows = Array.new(MessagesController::HISTORY_LIMIT + 5) do |index|
      { id: SecureRandom.uuid, conversation_id: newer.id, sender_id: employer.id, body: "bulk #{index}", created_at: base + index.seconds, updated_at: base }
    end
    Message.insert_all!(rows)
    get "/api/conversations/#{newer.id}/messages", headers: auth(candidate)
    assert_response :success
    bodies = response.parsed_body.fetch("messages").pluck("body")
    assert_equal MessagesController::HISTORY_LIMIT, bodies.size
    assert_equal "bulk 6", bodies.first
    assert_equal "second", bodies.last, "newest message last"
  end

  test "job listings report application counts without loading application rows" do
    employer = create_user("Count Employer", "employer")
    job = create_job(employer)
    3.times { |index| Application.create!(job:, candidate: create_user("Applicant #{index}", "jobseeker")) }
    candidate = create_user("Counting Candidate", "jobseeker")
    SavedJob.create!(user: candidate, job:)
    admin = create_user("Count Admin", "admin")

    loaded_applications = 0
    counter = ->(*, payload) { loaded_applications += 1 if payload[:name] == "Application Load" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/api/jobs"
      assert_response :success
      assert_equal 3, response.parsed_body.fetch("jobs").find { _1["id"] == job.id }.fetch("applicationsCount")
      assert_not response.parsed_body.fetch("jobs").first.key?("applications_total")

      get "/api/jobs/#{job.id}"
      assert_equal 3, response.parsed_body.dig("job", "applicationsCount")

      get "/api/saved-jobs", headers: auth(candidate)
      assert_equal [3], response.parsed_body.fetch("jobs").pluck("applicationsCount")

      get "/api/dashboard", headers: auth(employer)
      recent = response.parsed_body.fetch("recentJobs").find { _1["id"] == job.id }
      assert_equal [3, 3], recent.values_at("applicationsCount", "applications")

      get "/api/dashboard", headers: auth(candidate)
      assert_equal 3, response.parsed_body.fetch("recommendedJobs").find { _1["id"] == job.id }.fetch("applicationsCount")

      get "/api/admin/jobs", headers: auth(admin)
      assert_equal 3, response.parsed_body.fetch("jobs").find { _1["id"] == job.id }.fetch("applicationsCount")
    end
    assert_equal 0, loaded_applications
    assert_equal 3, Job.find(job.id).applications_count, "falls back to COUNT without the scope"
  end

  test "admin moderation lists are capped to the newest 500" do
    admin = create_user("List Admin", "admin")
    reporter = create_user("Bulk Reporter", "jobseeker")
    now = Time.current
    Report.insert_all!(Array.new(502) do |index|
      { id: SecureRandom.uuid, reporter_id: reporter.id, entity_type: "Job", entity_id: "x", reason: "spam", status: "open", created_at: now - index.minutes, updated_at: now }
    end)
    VerificationRequest.insert_all!(Array.new(502) do |index|
      { id: SecureRandom.uuid, user_id: reporter.id, kind: "professional", status: "pending", created_at: now - index.minutes, updated_at: now }
    end)
    employer = create_user("Bulk Employer", "employer")
    Review.insert_all!(Array.new(502) do |index|
      { id: SecureRandom.uuid, author_id: reporter.id, employer_id: employer.id, rating: 4, body: "bulk", status: "pending", created_at: now - index.minutes, updated_at: now }
    end)

    { "/api/admin/reports" => "reports", "/api/admin/verifications" => "requests", "/api/admin/reviews" => "reviews" }.each do |path, key|
      get path, headers: auth(admin)
      assert_response :success
      rows = response.parsed_body.fetch(key)
      assert_equal 500, rows.size, path
      assert_equal rows.pluck("created_at").sort.reverse, rows.pluck("created_at"), path
    end
  end

  test "public profiles do not leak synthetic batch and listings hide synthetic accounts from real users" do
    real = create_user("Organic Vocalist", "jobseeker", headline: "Playback vocalist")
    synthetic = create_user("QA Vocalist", "jobseeker", headline: "Playback vocalist")
    synthetic.update!(synthetic_batch: "qa-hidden-batch")
    synthetic_viewer = create_user("QA Viewer", "employer")
    synthetic_viewer.update!(synthetic_batch: "qa-hidden-batch")
    real_viewer = create_user("Real Viewer", "employer")

    get "/api/public/talent"
    ids = response.parsed_body.fetch("talent").pluck("id")
    assert_includes ids, real.id
    assert_not_includes ids, synthetic.id
    assert response.parsed_body.fetch("talent").none? { _1.key?("synthetic_batch") }

    get "/api/candidates", headers: auth(real_viewer)
    assert_not_includes response.parsed_body.fetch("candidates").pluck("id"), synthetic.id
    get "/api/candidates", headers: auth(synthetic_viewer)
    assert_includes response.parsed_body.fetch("candidates").pluck("id"), synthetic.id

    get "/api/search", params: { q: "Playback vocalist", type: "talent" }
    ids = response.parsed_body.fetch("results").pluck("id")
    assert_includes ids, real.id
    assert_not_includes ids, synthetic.id
    get "/api/search", params: { q: "Playback vocalist", type: "talent" }, headers: auth(synthetic_viewer)
    assert_includes response.parsed_body.fetch("results").pluck("id"), synthetic.id

    get "/api/public/talent/#{synthetic.id}"
    assert_response :success, "direct links to synthetic profiles still resolve"
    assert_not response.parsed_body.fetch("professional").key?("synthetic_batch")
  end

  test "duplicate reviews conflict and repeated saves succeed" do
    candidate = create_user("Repeat Reviewer", "jobseeker")
    employer = create_user("Reviewed Studio", "employer")
    job = create_job(employer)
    Application.create!(job:, candidate:, status: "Hired")

    post "/api/reviews", params: { employerId: employer.id, rating: 5, body: "Great engagement." }, headers: auth(candidate), as: :json
    assert_response :created
    post "/api/reviews", params: { employerId: employer.id, rating: 1, body: "Second attempt." }, headers: auth(candidate), as: :json
    assert_response :conflict
    assert_equal "REVIEW_EXISTS", response.parsed_body["code"]
    assert_equal 1, Review.where(author: candidate, employer:).count

    2.times do
      post "/api/saved-jobs/#{job.id}", headers: auth(candidate)
      assert_response :created
    end
    assert_equal 1, SavedJob.where(user: candidate, job:).count
  end

  test "saving a job treats a concurrent duplicate insert as success" do
    candidate = create_user("Racing Saver", "jobseeker")
    job = create_job(create_user("Racing Studio", "employer"))
    original = SavedJob.method(:find_or_create_by!)
    SavedJob.define_singleton_method(:find_or_create_by!) { |*| raise ActiveRecord::RecordNotUnique, "duplicate key value" }
    begin
      post "/api/saved-jobs/#{job.id}", headers: auth(candidate)
    ensure
      SavedJob.singleton_class.send(:remove_method, :find_or_create_by!)
    end
    assert_response :created
    assert_equal original, SavedJob.method(:find_or_create_by!)
  end

  test "job alert notifications link to the jobseeker opportunity route" do
    candidate = create_user("Alert Candidate", "jobseeker")
    job = create_job(create_user("Alert Studio", "employer"), title: "Alert Guitarist Opening")
    job.update!(published_at: 1.minute.ago)
    alert = candidate.job_alerts.create!(name: "Guitar", query: "Alert Guitarist", frequency: "daily", active: true)

    JobAlertDeliveryJob.perform_now(alert.id, 1.hour.ago, 1.minute.from_now)

    assert_equal ["/jobseeker/jobs/#{job.id}"], candidate.notifications.where(kind: "job_alert").pluck(:link)
  end

  test "database pool covers web and job threads" do
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test").first.configuration_hash
    expected = ENV.fetch("RAILS_MAX_THREADS", 5).to_i + ENV.fetch("GOOD_JOB_MAX_THREADS", 2).to_i + 3
    assert_equal expected, config[:pool].to_i
  end

  private

  def create_user(name, role, profile = {})
    @seq += 1
    email = "authz-#{@seq}-#{SecureRandom.hex(4)}@example.com"
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", profile_complete: true).tap do |user|
      user.create_profile!(profile) unless role == "admin"
    end
  end

  def create_job(employer, title: "Touring Music Professional")
    Job.create!(employer:, title:, company: "Contract Studio", location: "Mumbai", kind: "Contract",
      opportunity_kind: "tour", workplace: "onsite", genre: "Live", skills: ["Touring"], status: "published",
      description: "A properly documented professional opportunity with rehearsals, written terms and production support.")
  end

  def member_role(org, user) = org.organization_members.where(user:).pick(:role)

  def rate_key(bucket, user) = "user-rate:#{bucket}:#{user.id}:#{Time.current.to_i / 1.hour.to_i}"

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end
end
