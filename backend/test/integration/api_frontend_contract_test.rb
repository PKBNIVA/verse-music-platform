require "test_helper"
require_relative "../support/api_matrix_world"

# Response keys the React pages actually read (src/app/pages/*.tsx), per endpoint. A missing key
# renders as blank UI rather than an error, so drift is caught here instead of in the browser.
# `list => keys` checks the first element of the named array; nested lists use "list.child".
class ApiFrontendContractTest < ActionDispatch::IntegrationTest
  include ApiMatrixAssertions

  JOB_CARD = %w[id title company location opportunity_kind function_area workplace salary compensation_min compensation_max currency
                type genre skills employerVerified applicationsCount featured saved].freeze
  CONTRACTS = [
    # [page, actor, path, top-level keys, { list => item keys }]
    ["Navigation", :js, "/api/notifications/unread", %w[unread], {}],
    ["authContext", :js, "/api/me", %w[user], {}],
    ["ProfileSetup", :js, "/api/me", [], { "user" => %w[id name role email profileComplete emailVerified headline skills genres instruments languages credits openTo roles gear software] }],
    ["CompanyProfile", :emp, "/api/me", [], { "user" => %w[companyName companyWebsite companySize companyDescription verified] }],
    ["JobSearch/PublicJobs", nil, "/api/jobs", %w[jobs], { "jobs" => JOB_CARD }],
    ["JobDetails/PublicOpportunity", :js, "/api/jobs/{other_job}", %w[job], { "job" => %w[id title company description requirements location application_deadline start_date duration slots experience_level screeningQuestions applied saved employerVerified compensation_period] }],
    ["SavedJobs", :js, "/api/saved-jobs", %w[jobs], { "jobs" => %w[id title company location opportunity_kind workplace] }],
    ["ApplicationTracking", :js, "/api/applications", %w[applications], { "applications" => %w[id status title company location opportunityKind workplace createdAt interviewDate] }],
    ["JobAlerts", :js, "/api/job-alerts", %w[alerts], { "alerts" => %w[id name query location opportunity_kind function_area remote_only frequency active] }],
    ["JobSeekerDashboard", :js, "/api/dashboard", %w[applications interviews saved profileScore recommendedJobs], { "recommendedJobs" => %w[id title company location opportunity_kind workplace fitScore] }],
    ["EmployerDashboard", :emp, "/api/dashboard", %w[jobs published activeJobs applications shortlisted recentJobs], { "recentJobs" => %w[id title status location opportunity_kind workplace moderation_note applications] }],
    ["EmployerApplications", :emp, "/api/employer/applications", %w[applications], { "applications" => %w[id status jobId jobTitle candidateId candidateName candidateEmail candidateLocation experience skills coverLetter screeningAnswers recruiterNote recruiterRating allowedNextStatuses] }],
    ["Portfolio", :js, "/api/portfolio", %w[items], { "items" => %w[id type title url description creditedAs year featured thumbnailUrl waveformUrl visibility tags genres roles instruments mediaMetadata] }],
    ["Notifications", :js, "/api/notifications", %w[notifications unread], { "notifications" => %w[id title body link readAt createdAt type] }],
    ["Messages", :js, "/api/conversations", %w[conversations], { "conversations" => %w[id candidateName employerName jobTitle lastMessage] }],
    ["Messages", :js, "/api/conversations/{conversation}/messages", %w[messages], { "messages" => %w[id senderId body createdAt readAt] }],
    ["Availability", :js, "/api/availability", %w[windows], { "windows" => %w[id startAt endAt status city] }],
    ["CandidateSearch", :emp, "/api/candidates", %w[candidates], { "candidates" => %w[id name headline location skills verified bio shortlisted] }],
    ["CandidateSearch", :emp, "/api/candidates/{talent}", %w[candidate portfolio], { "candidate" => %w[id name headline] }],
    ["CandidateSearch", :emp, "/api/talent-folders", %w[folders], { "folders" => %w[id name count] }],
    ["CandidateSearch", :emp, "/api/recent-activity", %w[items], {}],
    ["CandidateCompare", :emp, "/api/candidates/compare/list?ids={talent},{peer_talent}", %w[professionals], { "professionals" => %w[id name headline location roles skills instruments verified yearsExperience sessionRate showRate tourDayRate currency travelsNationally passportReady remoteRecording sightReading portfolio availability] }],
    ["PublicTalent", nil, "/api/public/talent", %w[talent], { "talent" => %w[id name headline location roles instruments bio verified] }],
    ["PublicProfile", nil, "/api/public/talent/{talent}", %w[professional portfolio], { "professional" => %w[id name headline location bio roles instruments credits verified passportReady remoteRecording sightReading travelsNationally] }],
    ["PublicActs/BookTalent", nil, "/api/public/acts", %w[acts], { "acts" => %w[id name act_type city genres tagline bio verified min_fee ownerVerified] }],
    ["PublicAct", nil, "/api/public/acts/{act}", %w[act], { "act" => %w[name act_type bio tagline genres currency fee_basis min_fee max_fee verified members], "act.members" => %w[displayName roleName instrument] }],
    ["ActsManager", :js, "/api/acts/me", %w[acts], { "acts" => %w[id name act_type city genres fee_basis lineup_size min_fee max_fee status members], "acts.members" => %w[id displayName roleName instrument isLeader] }],
    ["BookTalent", :emp, "/api/acts?q=Act", %w[acts], { "acts" => %w[id name act_type city genres min_fee ownerVerified verified] }],
    ["Bookings", :js, "/api/bookings", %w[bookings], { "bookings" => %w[id status event_type event_date city currency actName requesterName isOwner isRequester latestQuote paymentCount created_at] }],
    ["Bookings", :js, "/api/bookings/{requested_booking}/payments", %w[payments], { "payments" => %w[id amount currency status kind] }],
    ["Workspace", :js, "/api/organizations", %w[organizations], { "organizations" => %w[id name memberCount memberRole] }],
    ["Workspace", :js, "/api/organizations/{org}/members", %w[members], { "members" => %w[id name email role] }],
    ["UrgentRequests", :js, "/api/urgent-requests", %w[requests], { "requests" => %w[id title role_name instrument city start_at currency status requester_id requesterVerified myResponse responseCount] }],
    ["UrgentRequests", :js, "/api/urgent-requests/{urgent}/responses", %w[responses], { "responses" => %w[user_id name headline message rate] }],
    ["BandBuilder", :js, "/api/band-projects", %w[projects], { "projects" => %w[id name city genres roles], "projects.roles" => %w[id role_name instrument count_needed compensation opportunity_id] }],
    ["BuildMyCrew", :js, "/api/crew-plans", %w[plans], { "plans" => %w[id title event_type city audience_size roles], "plans.roles" => %w[category roleName countNeeded priority rationale] }],
    ["Reviews", :js, "/api/reviews", %w[reviews eligibleEmployers], { "reviews" => %w[id rating title body authorName employerName] }],
    ["CareerResources", nil, "/api/resources", %w[resources], { "resources" => %w[id title category description url] }],
    ["Billing", :emp, "/api/billing/plans", %w[plans], { "plans" => %w[code name monthly trialDays activePosts seats shortlist bookings] }],
    ["Billing", :emp, "/api/billing/subscription", %w[subscription plan purchasedPlan], {}],
    ["GlobalSearch", nil, "/api/search?q=Matrix", %w[results interpretedAs], { "results" => %w[type id url title subtitle description tags] }],
    ["ActsManager/BandBuilder", nil, "/api/taxonomy", %w[opportunityKinds functionAreas workplaces currencies actTypes eventTypes engagementTypes roleCategories instruments], {}],
    ["AdminDashboard", :admin, "/api/admin/stats", %w[stats], {}],
    ["AdminDashboard", :admin, "/api/admin/users", %w[users], { "users" => %w[id name email role status verified] }],
    ["AdminDashboard", :admin, "/api/admin/jobs", %w[jobs], { "jobs" => %w[id title company status employerName employerVerified moderation_note salary compensation_min compensation_max currency location opportunity_kind workplace description] }],
    ["AdminDashboard", :admin, "/api/admin/reviews", %w[reviews], { "reviews" => %w[id rating title body status authorName employerName] }],
    ["AdminDashboard", :admin, "/api/admin/verifications", %w[requests], { "requests" => %w[id status name email role companyName] }],
    ["AdminDashboard", :admin, "/api/admin/reports", %w[reports], { "reports" => %w[id status entity_type entity_id reason details reporterName created_at] }],
    ["AdminDashboard", :admin, "/api/admin/audit", %w[logs], { "logs" => %w[id action entity_type entity_id actorName created_at] }],
    ["AdminDashboard", :admin, "/api/admin/subscriptions", %w[subscriptions], { "subscriptions" => %w[id plan_code status provider name email] }],
    ["AdminDashboard", :admin, "/api/admin/bookings", %w[bookings], { "bookings" => %w[id status event_type event_date city actName actOwner requesterName paidAmount] }],
    ["AdminTester", :admin, "/api/admin/tester", %w[summary checks generatedAt], {}]
  ].freeze

  test "every GET the frontend reads returns the keys its page uses" do
    world = ApiMatrixWorld.build
    seed_contract_rows(world)
    CONTRACTS.each do |page, actor, template, top, items|
      path = world.path(template, actor || :js)
      get path, headers: world.headers(actor)
      label = "#{page}: GET #{template}"
      assert_equal 200, response.status, "#{label}: #{response.body.first(200)}"
      body = parsed_json(label)
      assert_keys body, top, label
      items.each do |list_path, keys|
        sample = dig_first(body, list_path)
        assert sample, "#{label}: #{list_path} is empty; the contract world must seed a row"
        assert_keys sample, keys, "#{label} #{list_path}[]"
      end
    end
  end

  test "mutation responses expose the ids and fields pages read after writing" do
    world = ApiMatrixWorld.build
    js = world.headers(:js)
    emp = world.headers(:emp)
    post "/api/jobs", params: { title: "Contract draft", location: "Pune", description: "d" * 90, status: "draft" }, headers: emp, as: :json
    assert_keys response.parsed_body, %w[id status moderationFlags], "PostJob"
    post "/api/conversations", params: { candidateId: world.user(:js).id }, headers: emp, as: :json
    assert_keys response.parsed_body, %w[id conversation], "CandidateSearch message"
    post "/api/conversations/#{world.refs[:js][:conversation]}/messages", params: { body: "hi" }, headers: js, as: :json
    assert_keys response.parsed_body["message"], %w[id senderId body createdAt], "Messages send"
    post "/api/uploads/presign", params: { filename: "a.mp3", contentType: "audio/mpeg", size: 10 }, headers: js, as: :json
    assert_keys response.parsed_body, %w[mode uploadUrl], "uploadMedia presign"
    post "/api/bookings/#{world.refs[:js][:owned_booking]}/quote", params: { performanceFee: 100 }, headers: js, as: :json
    assert_keys response.parsed_body, %w[id total], "Bookings quote"
    post "/api/crew-plans", params: { title: "Gala", eventType: "gala", city: "Pune", needs: ["sound"] }, headers: js, as: :json
    assert_keys response.parsed_body, %w[id roles], "BuildMyCrew create"
    post "/api/crew-plans/#{world.refs[:js][:plan]}/convert", headers: js, as: :json
    assert_keys response.parsed_body, %w[projectId], "BuildMyCrew convert"
    post "/api/auth/request-email-verification", headers: js, as: :json
    assert response.parsed_body.key?("alreadyVerified") || response.parsed_body.key?("ok"), "ProfileSetup verification"
    post "/api/auth/login", params: { email: world.user(:js).email, password: ApiMatrixWorld::PASSWORD }, as: :json
    assert_keys response.parsed_body, %w[user accessToken], "authContext login"
    assert_keys response.parsed_body["user"], %w[id role profileComplete], "AuthPage redirect"
    patch "/api/employer/applications/#{world.refs[:emp][:received_application]}", params: { status: "Shortlisted" }, headers: emp, as: :json
    assert_keys response.parsed_body["application"], %w[id status allowedNextStatuses], "EmployerApplications update"
  end

  private

  def seed_contract_rows(world)
    js = world.user(:js)
    world.refs[:js][:peer_talent] = world.user(:js2).id
    world.refs[:emp][:peer_talent] = world.user(:js2).id
    UrgentRequestResponse.create!(urgent_request_id: world.refs[:js][:urgent], user: world.user(:emp), message: "Free", rate: 100, status: "available")
    BandProject.find(world.refs[:js][:project]).update!(city: "Pune")
    Act.find(world.refs[:js][:act]).touch # most recent first: the act with a lineup

    RecentActivity.create!(user: world.user(:emp), kind: "profile_view", entity_id: js.id, label: js.name)
    AuditLog.create!(actor: js, action: "contract.seed", entity_type: "User", entity_id: js.id)
    Subscription.create!(user: world.user(:emp), plan_code: "pro", provider: "internal", status: "active", current_period_end: 10.days.from_now)
  end

  def dig_first(body, list_path)
    list_path.split(".").reduce(body) do |node, key|
      node = node.first if node.is_a?(Array)
      node.is_a?(Hash) ? node[key] : nil
    end.then { _1.is_a?(Array) ? _1.first : _1 }
  end
end
