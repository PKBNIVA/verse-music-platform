require "test_helper"

class ApiContractTest < ActionDispatch::IntegrationTest
  HTTP_METHODS = {
    "Get" => :get,
    "Post" => :post,
    "Put" => :put,
    "Patch" => :patch,
    "Delete" => :delete
  }.freeze

  test "every literal frontend API consumer resolves to a Rails route with the same method" do
    consumers = frontend_api_consumers

    assert_operator consumers.length, :>=, 100, "API consumer scanner stopped finding expected calls"
    # /api/dev/razorpay/* exists only while the local Razorpay simulator is enabled.
    simulator_env = { "RAZORPAY_SIMULATOR" => "true", "RAZORPAY_KEY_ID" => "rzp_test_contract" }
    previous = simulator_env.to_h { [_1, ENV[_1]] }
    ENV.update(simulator_env)
    consumers.each do |consumer|
      begin
        Rails.application.routes.recognize_path(consumer[:path], method: consumer[:method])
      rescue StandardError => error
        flunk "#{consumer[:source]} calls missing #{consumer[:method].upcase} #{consumer[:path]}: #{error.message}"
      end
    end
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "anonymous discovery endpoints keep their browser-facing response contracts" do
    employer = create_user("Public Employer", "public-employer@example.com", "employer", company_name: "Public Studio")
    candidate = create_user("Public Artist", "public-artist@example.com", "jobseeker",
      headline: "Touring vocalist", location: "Mumbai", skills: ["Vocals"])
    job = create_job(employer, status: "published")
    act = Act.create!(owner: candidate, name: "Public Ensemble", act_type: "band", status: "active",
      currency: "INR", fee_basis: "event", city: "Mumbai", genres: ["Jazz"])
    act.act_members.create!(user: candidate, display_name: candidate.name, role_name: "Vocalist",
      is_leader: true, member_status: "confirmed")

    get "/api/jobs"
    assert_response :success
    listing = response.parsed_body.fetch("jobs").find { _1["id"] == job.id }
    assert_contract listing, %w[id title company location status opportunity_kind employerName employerVerified createdAt saved]
    assert_kind_of Array, listing.fetch("skills")
    assert_includes [true, false], listing.fetch("saved")

    get "/api/jobs/#{job.id}"
    assert_response :success
    assert_contract response.parsed_body, %w[job]
    assert_contract response.parsed_body.fetch("job"), %w[id title company description employerName employerVerified applied saved]

    get "/api/public/talent"
    assert_response :success
    professional = response.parsed_body.fetch("talent").find { _1["id"] == candidate.id }
    assert_contract professional, %w[id name role headline location skills verified]
    assert_no_contract_keys professional, %w[email phone status profileComplete emailVerified]

    get "/api/public/acts"
    assert_response :success
    public_act = response.parsed_body.fetch("acts").find { _1["id"] == act.id }
    assert_contract public_act, %w[id name act_type status city genres members ownerName ownerVerified]
    assert_no_contract_keys public_act, %w[owner_id tech_rider_url hospitality_rider_url]
  end

  test "jobseeker endpoints keep authenticated dashboard and application contracts" do
    employer = create_user("Hiring Employer", "contract-employer@example.com", "employer", company_name: "Hiring Studio")
    candidate = create_user("Contract Candidate", "contract-candidate@example.com", "jobseeker",
      headline: "Session guitarist", location: "Delhi", skills: ["Guitar"])
    job = create_job(employer, status: "published")
    application = job.applications.create!(candidate:, status: "Applied", cover_letter: "Ready to tour")
    token = session_for(candidate)
    candidate.notifications.create!(kind: "application", title: "Application received", link: "/jobseeker/applications")

    get "/api/me", headers: auth(token)
    assert_response :success
    assert_contract response.parsed_body.fetch("user"), %w[id name email role status profileComplete emailVerified headline skills]

    get "/api/dashboard", headers: auth(token)
    assert_response :success
    assert_contract response.parsed_body, %w[applications interviews saved profileScore recommendedJobs]
    assert_kind_of Array, response.parsed_body.fetch("recommendedJobs")

    get "/api/applications", headers: auth(token)
    assert_response :success
    item = response.parsed_body.fetch("applications").find { _1["id"] == application.id }
    assert_contract item, %w[id jobId status coverLetter createdAt updatedAt opportunityKind workplace title company location]

    get "/api/notifications", headers: auth(token)
    assert_response :success
    assert_contract response.parsed_body, %w[notifications unread]
    notification = response.parsed_body.fetch("notifications").first
    assert_contract notification, %w[id kind title link createdAt readAt]
  end

  test "employer and admin endpoints keep operational response contracts" do
    employer = create_user("Contract Studio", "ops-employer@example.com", "employer", company_name: "Contract Studio")
    candidate = create_user("Ops Candidate", "ops-candidate@example.com", "jobseeker",
      headline: "FOH engineer", location: "Bengaluru", skills: ["FOH"])
    job = create_job(employer, status: "published")
    application = job.applications.create!(candidate:, status: "Applied")
    employer_token = session_for(employer)

    get "/api/dashboard", headers: auth(employer_token)
    assert_response :success
    assert_contract response.parsed_body, %w[jobs published activeJobs applications shortlisted recentJobs]
    recent = response.parsed_body.fetch("recentJobs").find { _1["id"] == job.id }
    assert_contract recent, %w[id title location status applications]

    get "/api/employer/applications", headers: auth(employer_token)
    assert_response :success
    applicant = response.parsed_body.fetch("applications").find { _1["id"] == application.id }
    assert_contract applicant, %w[id jobId jobTitle candidateId candidateName candidateEmail candidateLocation skills verified status]

    get "/api/candidates", headers: auth(employer_token)
    assert_response :success
    talent = response.parsed_body.fetch("candidates").find { _1["id"] == candidate.id }
    assert_contract talent, %w[id name headline location skills verified shortlisted]
    assert_no_contract_keys talent, %w[email phone]

    admin = create_user("Contract Admin", "contract-admin@example.com", "admin")
    admin_token = session_for(admin)

    get "/api/admin/stats", headers: auth(admin_token)
    assert_response :success
    assert_contract response.parsed_body.fetch("stats"),
      %w[users jobseekers employers jobs liveJobs applications hires pendingJobs openReports bookings activeSubscriptions]

    get "/api/admin/users", headers: auth(admin_token)
    assert_response :success
    admin_user = response.parsed_body.fetch("users").find { _1["id"] == candidate.id }
    assert_contract admin_user, %w[id name email role status verified]

    get "/api/admin/jobs", headers: auth(admin_token)
    assert_response :success
    admin_job = response.parsed_body.fetch("jobs").find { _1["id"] == job.id }
    assert_contract admin_job, %w[id title company status employerName employerVerified createdAt]
  end

  private

  def frontend_api_consumers
    frontend_root = Rails.root.join("..", "src", "app")
    pattern = /api(Get|Post|Put|Patch|Delete)(?:<[^>]*>)?\(\s*([`'"])(.*?)\2/m

    Dir.glob(frontend_root.join("**", "*.{ts,tsx}")).flat_map do |source|
      File.read(source).scan(pattern).filter_map do |verb, _, raw_path|
        next unless raw_path.start_with?("/")

        path = raw_path.gsub(/\$\{[^}]+\}/, "1").split("?", 2).first
        {
          method: HTTP_METHODS.fetch(verb),
          path: "/api#{path}",
          source: Pathname(source).relative_path_from(frontend_root).to_s
        }
      end
    end.uniq { [_1[:method], _1[:path]] }
  end

  def create_user(name, email, role, profile = {})
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", profile_complete: true).tap do |user|
      user.create_profile!(profile) unless role == "admin"
    end
  end

  def create_job(employer, status:)
    Job.create!(employer:, title: "Touring Music Professional", company: "Contract Studio", location: "Mumbai",
      kind: "Contract", opportunity_kind: "tour", workplace: "onsite", genre: "Live", skills: ["Touring"],
      description: "A properly documented professional opportunity with rehearsals, written terms and production support.",
      status:)
  end

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def assert_contract(payload, required_keys)
    assert_kind_of Hash, payload
    required_keys.each { |key| assert payload.key?(key), "Expected response to include #{key}; got #{payload.keys.sort}" }
  end

  def assert_no_contract_keys(payload, forbidden_keys)
    forbidden_keys.each { |key| assert_not payload.key?(key), "Response leaked forbidden key #{key}" }
  end
end
