require "test_helper"

# Poster-side hiring: drafts, editing, publishing within plan limits, crew plans and talent folders.
class EmployerHiringTest < ActionDispatch::IntegrationTest
  DESCRIPTION = "Record layered guitar parts for a feature film score over three sessions with the composer present.".freeze

  setup do
    @employer = make_user("Hiring Studio", "hire@example.com", "employer")
    @token = session_for(@employer)
  end

  test "a draft saves with only a title, is edited and then submitted for review" do
    post "/api/jobs", params: { status: "draft", title: "Session guitarist" }, headers: auth, as: :json
    assert_response :created
    job_id = response.parsed_body.fetch("id")
    assert_equal "draft", Job.find(job_id).status

    get "/api/employer/jobs", headers: auth
    assert_response :success
    listed = response.parsed_body.fetch("jobs").find { _1["id"] == job_id }
    assert_equal %w[pending closed], listed.fetch("allowedNextStatuses")

    patch "/api/employer/jobs/#{job_id}", params: { status: "pending" }, headers: auth, as: :json
    assert_response :unprocessable_entity
    assert_match(/Location can't be blank/, response.parsed_body.fetch("error"))
    assert_equal "draft", Job.find(job_id).status

    patch "/api/employer/jobs/#{job_id}", params: { location: "Mumbai", description: DESCRIPTION, compensationMin: 20_000, compensationMax: 30_000, skills: ["Guitar"] }, headers: auth, as: :json
    assert_response :success
    assert_equal "draft", response.parsed_body.dig("job", "status")

    patch "/api/employer/jobs/#{job_id}", params: { status: "pending" }, headers: auth, as: :json
    assert_response :success
    job = Job.find(job_id)
    assert_equal "pending", job.status
    assert_equal ["Guitar"], job.skills
    assert_nil job.moderation_note
  end

  test "submitting or reopening respects the plan's active post limit" do
    post "/api/jobs", params: complete_job(title: "First live post"), headers: auth, as: :json
    assert_response :created
    first_id = response.parsed_body.fetch("id")
    post "/api/jobs", params: complete_job(title: "Second post").merge(status: "draft"), headers: auth, as: :json
    assert_response :created
    draft_id = response.parsed_body.fetch("id")

    # The free plan allows one active opportunity.
    patch "/api/employer/jobs/#{draft_id}", params: { status: "pending" }, headers: auth, as: :json
    assert_response :payment_required
    assert_equal "PLAN_LIMIT", response.parsed_body.fetch("code")
    assert_equal "draft", Job.find(draft_id).status

    patch "/api/employer/jobs/#{first_id}", params: { status: "closed" }, headers: auth, as: :json
    assert_response :success
    patch "/api/employer/jobs/#{draft_id}", params: { status: "pending" }, headers: auth, as: :json
    assert_response :success

    patch "/api/employer/jobs/#{first_id}", params: { status: "pending" }, headers: auth, as: :json
    assert_response :payment_required
    assert_equal "closed", Job.find(first_id).status

    # Edits to an opportunity that already counts against the limit are not blocked by it.
    patch "/api/employer/jobs/#{draft_id}", params: { title: "Second post, revised" }, headers: auth, as: :json
    assert_response :success
  end

  test "editing a live opportunity sends it back to review and only the owner may edit" do
    job = @employer.jobs.create!(complete_attributes.merge(status: "published", published_at: Time.current))

    patch "/api/employer/jobs/#{job.id}", params: { description: "#{DESCRIPTION} Contact us on WhatsApp for details." }, headers: auth, as: :json
    assert_response :success
    job.reload
    assert_equal "pending", job.status
    assert_match(/off-platform/, job.moderation_note)

    other = make_user("Other Studio", "other@example.com", "employer")
    patch "/api/employer/jobs/#{job.id}", params: { title: "Hijacked" }, headers: auth(session_for(other)), as: :json
    assert_response :not_found

    patch "/api/employer/jobs/#{job.id}", params: {}, headers: auth, as: :json
    assert_response :bad_request

    patch "/api/employer/jobs/#{job.id}", params: { status: "closed" }, headers: auth, as: :json
    assert_response :success
    patch "/api/employer/jobs/#{job.id}", params: { title: "Quiet edit" }, headers: auth, as: :json
    assert_response :conflict

    published = @employer.jobs.create!(complete_attributes.merge(title: "Live", status: "published"))
    patch "/api/employer/jobs/#{published.id}", params: { status: "draft" }, headers: auth, as: :json
    assert_response :conflict
    patch "/api/employer/jobs/#{published.id}", params: { status: { x: 1 } }, headers: auth, as: :json
    assert_response :bad_request
  end

  test "an incomplete draft can be closed" do
    post "/api/jobs", params: { status: "draft", title: "Abandoned idea" }, headers: auth, as: :json
    job_id = response.parsed_body.fetch("id")
    patch "/api/employer/jobs/#{job_id}", params: { status: "closed" }, headers: auth, as: :json
    assert_response :success
    assert_equal "closed", Job.find(job_id).status
  end

  test "job fields are validated instead of raising" do
    post "/api/jobs", params: complete_job(compensationMin: 500, compensationMax: 100), headers: auth, as: :json
    assert_response :unprocessable_entity
    assert_match(/at least the minimum/, response.parsed_body.fetch("error"))

    post "/api/jobs", params: complete_job(slots: 0), headers: auth, as: :json
    assert_response :unprocessable_entity

    post "/api/jobs", params: complete_job(compensationMin: 99_999_999_999), headers: auth, as: :json
    assert_response :unprocessable_entity

    post "/api/jobs", params: complete_job(applicationDeadline: "2020-01-01"), headers: auth, as: :json
    assert_response :unprocessable_entity
    assert_match(/deadline/, response.parsed_body.fetch("error"))

    post "/api/jobs", params: complete_job(screeningQuestions: Array.new(9) { "Question #{_1}?" }), headers: auth, as: :json
    assert_response :unprocessable_entity

    post "/api/jobs", params: complete_job(compensationMin: 1000).except(:compensationMax), headers: auth, as: :json
    assert_response :created
    assert_nil Job.find(response.parsed_body.fetch("id")).compensation_max
  end

  test "crew plans validate input and cover every need" do
    post "/api/crew-plans", params: {}, headers: auth, as: :json
    assert_response :unprocessable_entity
    post "/api/crew-plans", params: { title: "Gala", city: "Goa", eventDate: "not a date" }, headers: auth, as: :json
    assert_response :unprocessable_entity
    post "/api/crew-plans", params: { title: "Gala", city: "Goa", needs: { a: 1 } }, headers: auth, as: :json
    assert_response :unprocessable_entity
    post "/api/crew-plans", params: { title: "Gala", city: "Goa", budget: 99_999_999_999 }, headers: auth, as: :json
    assert_response :unprocessable_entity

    post "/api/crew-plans", params: { title: "Gala", city: "Goa", needs: "video", eventDate: "2027-01-10" }, headers: auth, as: :json
    assert_response :created
    assert_equal ["Video Director", "Camera Operator"], response.parsed_body.fetch("roles").pluck("roleName")
    plan_id = response.parsed_body.fetch("id")

    post "/api/crew-plans/#{plan_id}/convert", headers: auth, as: :json
    assert_response :created
    assert_equal 2, BandProject.find(response.parsed_body.fetch("projectId")).band_project_roles.count
  end

  test "talent folders reject blank names, count members and delete with members" do
    post "/api/talent-folders", params: { name: "  " }, headers: auth, as: :json
    assert_response :unprocessable_entity
    post "/api/talent-folders", params: {}, headers: auth, as: :json
    assert_response :unprocessable_entity

    post "/api/talent-folders", params: { name: "Tour band" }, headers: auth, as: :json
    assert_response :created
    folder_id = response.parsed_body.fetch("id")
    candidate = make_user("Working Drummer", "drums@example.com", "jobseeker")
    post "/api/talent-folders/#{folder_id}/candidates/#{candidate.id}", params: { note: "Great feel" }, headers: auth, as: :json
    assert_response :created

    get "/api/talent-folders", headers: auth
    assert_equal 1, response.parsed_body.fetch("folders").first.fetch("count")

    delete "/api/talent-folders/#{folder_id}", headers: auth
    assert_response :success
    assert_not TalentFolder.exists?(folder_id)
    assert_equal 0, TalentFolderMember.where(talent_folder_id: folder_id).count
  end

  test "list and filter parameters must be single values" do
    get "/api/candidates", params: { q: ["a"] }, headers: auth
    assert_response :bad_request
    assert_equal "INVALID_PARAMETER", response.parsed_body.fetch("code")
    get "/api/public/talent", params: { location: { x: "y" } }
    assert_response :bad_request
    get "/api/employer/applications", params: { jobId: { x: "y" } }, headers: auth
    assert_response :bad_request
    get "/api/candidates/compare/list", params: { ids: ["a", "b"] }, headers: auth
    assert_response :bad_request
  end

  private

  def complete_attributes
    { title: "Film score guitarist", company: "Hiring Studio", location: "Mumbai", kind: "Contract", genre: "Film", description: DESCRIPTION, compensation_min: 20_000, compensation_max: 30_000 }
  end

  def complete_job(overrides = {})
    { title: "Film score guitarist", location: "Mumbai", description: DESCRIPTION, compensationMin: 20_000, compensationMax: 30_000 }.merge(overrides)
  end

  def make_user(name, email, role)
    user = User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", profile_complete: true)
    user.create_profile!(headline: name)
    user
  end

  def auth(token = @token) = { "Authorization" => "Bearer #{token}" }

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
