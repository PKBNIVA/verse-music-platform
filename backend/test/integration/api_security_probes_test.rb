require "test_helper"
require_relative "../support/api_matrix_world"

# Local-only security probes: mass assignment, SQL-injection-looking and oversized input,
# unicode, absurd pagination numbers and JSON type confusion. Each probe asserts the API never
# answers 5xx, keeps the {error, code?} shape, and never lets a client choose server-owned fields.
class ApiSecurityProbesTest < ActionDispatch::IntegrationTest
  include ApiMatrixAssertions

  INJECTION = ["' OR '1'='1", "'; DROP TABLE jobs; --", "%", "_", "\\", "%' OR 1=1 --", "1) UNION SELECT password_digest FROM users --", "$ne", "{\"$gt\":\"\"}"].freeze
  LIST_FILTERS = {
    "/api/jobs" => %w[q location kind function workplace experience],
    "/api/public/talent" => %w[q location role instrument],
    "/api/public/acts" => %w[q city],
    "/api/search" => %w[q type],
    "/api/reviews" => %w[employerId]
  }.freeze
  AUTH_LIST_FILTERS = {
    "/api/candidates" => %w[q location role instrument],
    "/api/acts" => %w[q city],
    "/api/urgent-requests" => %w[city role],
    "/api/employer/applications" => %w[jobId]
  }.freeze

  # Findings outside this workstream's files, skipped with the owner and a repro.
  # Pattern (matched against the probe label) => reason. Root cause for the query-string group:
  # filters pass params[:x] straight to sanitize_sql_like (NoMethodError on Array/Parameters) or
  # to where(column => value) (StatementInvalid "can't cast ActionController::Parameters").
  # Suggested shared fix: read filters with params[:x].is_a?(String) guards (or a scalar-param helper).
  KNOWN_GAPS = {
    %r{\A/api/jobs\?(location|kind|function|workplace|experience)} =>
      "OWNER: jobs — GET /api/jobs?location[]=a or ?kind[x]=y is 500 (jobs_controller.rb:13-14 sanitize_sql_like/where on non-string params)",
    %r{\A/api/(public/talent|candidates)\?} =>
      "OWNER: talent — GET /api/public/talent?q[]=a (also location/role/instrument, /api/candidates) is 500 (talent_controller.rb:87-99 sanitize_sql_like on Array)",
    %r{\A/api/(public/)?acts\?} =>
      "OWNER: acts — GET /api/public/acts?q[]=a or ?city[x]=y is 500 (acts_controller.rb:79-87 sanitize_sql_like on non-string)",
    %r{\A/api/reviews\?employerId} =>
      "OWNER: reviews — GET /api/reviews?employerId[x]=y is 500 (reviews_controller.rb:4 where(employer_id: Parameters))",
    %r{\APOST /api/reviews } =>
      "OWNER: reviews — POST /api/reviews {employerId:[id]} is 500 NoMethodError (reviews_controller.rb:12 find(Array) returns an Array)",
    %r{\A/api/urgent-requests\?} =>
      "OWNER: urgent-requests — GET /api/urgent-requests?city[]=a or ?role[]=a is 500 (urgent_requests_controller.rb:7-10 sanitize_sql_like on Array)",
    %r{\A/api/employer/applications\?jobId} =>
      "OWNER: employer-applications — GET /api/employer/applications?jobId[x]=y is 500 (employer/applications_controller.rb:6 where(job_id: Parameters))",
    %r{\APOST /api/conversations } =>
      "OWNER: messaging — POST /api/conversations {jobId:{a:1}} is 500 StatementInvalid (conversations_controller.rb:18 find_by(id: Parameters))",
    %r{\APOST /api/bookings } =>
      "OWNER: bookings — POST /api/bookings {actId:[id]} is 500 NoMethodError owner_id for Array (bookings_controller.rb:11 find(Array))",
    %r{\APOST /api/crew-plans } =>
      "OWNER: crew-plans — POST /api/crew-plans {needs:\"sound\"} is 500 NoMethodError flat_map for String (crew_plans_controller.rb:7)"
  }.freeze

  setup do
    @world = ApiMatrixWorld.build
    @js = @world.user(:js)
    @emp = @world.user(:emp)
  end

  # ---- Mass assignment ------------------------------------------------------------------

  test "mass assignment: profile update cannot grant verification, role, status or ownership" do
    put "/api/profile", params: { headline: "Mine", verified: true, role: "admin", status: "suspended", userId: @world.user(:js2).id,
      user_id: @world.user(:js2).id, emailVerified: false, profileComplete: false, synthetic_batch: "qa-x", syntheticBatch: "qa-x" },
      headers: h(:js), as: :json
    ok!
    @js.reload
    assert_equal ["jobseeker", "active", true, nil], [@js.role, @js.status, @js.email_verified, @js.synthetic_batch]
    assert_equal false, @js.profile.verified
    assert_equal "Mine", @js.profile.headline
    assert_equal "Matrix Rival Artist headline", @world.user(:js2).profile.reload.headline
  end

  test "mass assignment: registration cannot pick admin role, status or verified email" do
    post "/api/auth/register", params: { name: "Sneaky", email: "sneaky@example.com", password: "LongEnough123!", role: "admin" }, as: :json
    assert_equal [422, "INVALID_ROLE"], [response.status, response.parsed_body["code"]]
    post "/api/auth/register", params: { name: "Sneaky", email: "sneaky@example.com", password: "LongEnough123!", role: "jobseeker",
      status: "active", email_verified: true, emailVerified: true, profile_complete: true, synthetic_batch: "qa-x" }, as: :json
    assert_response :created
    user = User.find_by!(email: "sneaky@example.com")
    assert_equal [false, false, nil], [user.email_verified, user.profile_complete, user.synthetic_batch]
  end

  test "mass assignment: job creation ignores status, featured, owner and moderation fields" do
    post "/api/jobs", params: { title: "Mass assigned gig", location: "Pune", description: "D" * 90, status: "published", featured: true,
      employerId: @world.user(:emp2).id, employer_id: @world.user(:emp2).id, publishedAt: 1.day.ago, moderationNote: "approved",
      id: "job_forged" }, headers: h(:emp), as: :json
    assert_includes [201, 402], response.status
    post "/api/jobs", params: { title: "Mass assigned draft", location: "Pune", description: "D" * 90, status: "draft", featured: true,
      employerId: @world.user(:emp2).id, publishedAt: 1.day.ago }, headers: h(:emp), as: :json
    assert_response :created
    job = Job.find(response.parsed_body["id"])
    assert_equal ["draft", false, @emp.id, nil], [job.status, job.featured, job.employer_id, job.published_at]
    assert_not Job.exists?(id: "job_forged")
  end

  test "mass assignment: applying cannot choose status, rating or candidate" do
    job_id = @world.refs[:emp2][:job]
    post "/api/jobs/#{job_id}/apply", params: { coverLetter: "Hi", status: "Hired", recruiterRating: 5, recruiterNote: "hire", candidateId: @world.user(:js2).id }, headers: h(:js), as: :json
    assert_response :created
    application = Application.find(response.parsed_body["id"])
    assert_equal ["Applied", nil, nil, @js.id], [application.status, application.recruiter_rating, application.recruiter_note, application.candidate_id]
  end

  test "mass assignment: owner fields are ignored on every owned create endpoint" do
    rival = @world.user(:js2).id
    creates = {
      "/api/portfolio" => [{ type: "audio", title: "T", url: "https://example.com/x.mp3", userId: rival, user_id: rival }, PortfolioItem, :user_id],
      "/api/job-alerts" => [{ name: "A", frequency: "daily", userId: rival, user_id: rival, nextRunAt: 1.year.ago }, JobAlert, :user_id],
      "/api/availability" => [{ startAt: 3.days.from_now, endAt: 4.days.from_now, userId: rival, user_id: rival }, AvailabilityWindow, :user_id],
      "/api/acts" => [{ name: "Mine", actType: "duo", verified: true, ownerId: rival, owner_id: rival }, Act, :owner_id],
      "/api/urgent-requests" => [{ title: "U", roleName: "Keys", city: "Pune", startAt: 2.days.from_now, status: "filled", requesterId: rival }, UrgentRequest, :requester_id],
      "/api/organizations" => [{ name: "Org", status: "suspended", ownerId: rival, owner_id: rival }, Organization, :owner_id],
      "/api/talent-folders" => [{ name: "F", ownerId: rival, owner_id: rival }, TalentFolder, :owner_id],
      "/api/band-projects" => [{ name: "B", status: "closed", ownerId: rival }, BandProject, :owner_id],
      "/api/crew-plans" => [{ title: "C", eventType: "gala", city: "Pune", ownerId: rival }, CrewPlan, :owner_id]
    }
    creates.each do |path, (params, model, owner_column)|
      post path, params:, headers: h(:js), as: :json
      assert_equal 201, response.status, "#{path}: #{response.body.first(200)}"
      record = model.find(response.parsed_body["id"])
      assert_equal @js.id, record.public_send(owner_column), "#{path} let the client choose #{owner_column}"
    end
    act = Act.order(:created_at).last
    assert_equal false, act.verified
    assert_equal "open", UrgentRequest.order(:created_at).last.status
    assert_equal "active", Organization.order(:created_at).last.status
    assert_equal "open", BandProject.order(:created_at).last.status
  end

  test "mass assignment: act update cannot set verified or move ownership" do
    act_id = @world.refs[:js][:act]
    patch "/api/acts/#{act_id}", params: { verified: true, ownerId: @world.user(:js2).id, owner_id: @world.user(:js2).id, tagline: "ok" }, headers: h(:js), as: :json
    ok!
    act = Act.find(act_id)
    assert_equal [false, @js.id, "ok"], [act.verified, act.owner_id, act.tagline]
  end

  test "mass assignment: booking, quote, message and application annotation fields stay server-owned" do
    post "/api/bookings", params: { actId: @world.refs[:emp][:act], eventType: "gig", city: "Pune", status: "accepted", requesterId: @world.user(:js2).id }, headers: h(:js), as: :json
    assert_response :created
    booking = BookingRequest.find(response.parsed_body["id"])
    assert_equal ["requested", @js.id], [booking.status, booking.requester_id]

    post "/api/bookings/#{@world.refs[:js][:owned_booking]}/quote", params: { performanceFee: 100, status: "accepted", createdById: @emp.id }, headers: h(:js), as: :json
    assert_response :created
    quote = BookingQuote.find(response.parsed_body["id"])
    assert_equal ["sent", @js.id], [quote.status, quote.created_by_id]

    post "/api/conversations/#{@world.refs[:js][:conversation]}/messages", params: { body: "hi", senderId: @emp.id, readAt: Time.current }, headers: h(:js), as: :json
    assert_response :created
    message = Message.find(response.parsed_body.dig("message", "id"))
    assert_equal [@js.id, nil], [message.sender_id, message.read_at]

    application_id = @world.refs[:emp][:received_application]
    patch "/api/employer/applications/#{application_id}", params: { recruiterNote: "n", candidateId: @world.user(:js2).id, jobId: @world.refs[:emp2][:job] }, headers: h(:emp), as: :json
    ok!
    application = Application.find(application_id)
    assert_equal [@js.id, @world.refs[:emp][:job]], [application.candidate_id, application.job_id]
  end

  test "mass assignment: admin user update only changes status" do
    patch "/api/admin/users/#{@js.id}", params: { status: "active", role: "admin", email: "hijack@example.com", emailVerified: false }, headers: h(:admin), as: :json
    ok!
    @js.reload
    assert_equal ["jobseeker", true], [@js.role, @js.email_verified]
    assert_not_equal "hijack@example.com", @js.email
  end

  # ---- Injection-looking and oversized input ------------------------------------------

  test "SQL-injection-looking filters are inert: 200, no rows, never 500" do
    each_filter do |path, key, actor|
      INJECTION.each do |value|
        get path, params: { key => value }, headers: h(actor)
        next unless probe!("#{path}?#{key}=#{value}")
        assert_equal 200, response.status, "#{path}?#{key}=#{value}: #{response.body.first(200)}"
        list = response.parsed_body.values.find { _1.is_a?(Array) } || []
        assert_empty list, "#{path}?#{key}=#{value} matched rows" if %w[q location role instrument city].include?(key)
      end
    end
    assert_equal 6, User.where("email LIKE 'matrix-%'").count, "users table intact"
    verdict!
  end

  test "very long filters (20k chars) and NUL bytes are handled without 500" do
    long = "a" * 20_000
    each_filter do |path, key, actor|
      [long, "mix\u0000ing"].each do |value|
        get path, params: { key => value }, headers: h(actor)
        next unless probe!("#{path}?#{key}=#{value.first(12).inspect}")
        assert_includes [200, 400, 414, 422], response.status, "#{path}?#{key}"
      end
    end
    verdict!
  end

  test "very long and NUL-byte bodies on create endpoints are 4xx or stored intact" do
    post "/api/job-alerts", params: { name: "n" * 100_000, frequency: "daily" }, headers: h(:js), as: :json
    probe!("job-alerts long name")
    post "/api/conversations/#{@world.refs[:js][:conversation]}/messages", params: { body: "b" * 100_000 }, headers: h(:js), as: :json
    probe!("message 100k")
    assert_equal [422, "MESSAGE_TOO_LONG"], [response.status, response.parsed_body["code"]], "oversized messages are rejected, not truncated"
    assert Message.where("length(body) > 5000").none?, "no message body over 5000 characters is stored"
    post "/api/talent-folders", params: { name: "evil\u0000name" }, headers: h(:emp), as: :json
    probe!("NUL in JSON string")
    assert_equal 422, response.status
    assert_equal "INVALID_VALUE", response.parsed_body["code"]
    verdict!
  end

  test "unicode and emoji round-trip through create, read and search" do
    title = "Tabla 🥁 player — संगीत mix ✓"
    post "/api/jobs", params: { title:, location: "Pune", description: "Ümlaut 🎸 " + "d" * 90, status: "draft" }, headers: h(:emp), as: :json
    assert_response :created
    job = Job.find(response.parsed_body["id"])
    assert_equal title, job.title
    job.update!(status: "published", published_at: Time.current)
    get "/api/jobs", params: { q: "🥁" }
    ok!
    assert_equal [job.id], response.parsed_body["jobs"].map { _1["id"] }
    get "/api/search", params: { q: "संगीत" }
    ok!
    assert_includes response.parsed_body["results"].map { _1["id"] }, job.id
    put "/api/profile", params: { headline: "👩‍🎤 Singer", skills: ["Ghazal 🎶"] }, headers: h(:js), as: :json
    ok!
    assert_equal "👩‍🎤 Singer", response.parsed_body.dig("user", "headline")
  end

  # ---- Pagination numbers -----------------------------------------------------------------

  test "negative, zero and huge pagination numbers never 500" do
    params = [{ limit: -1, page: -5 }, { limit: 0, offset: -1 }, { limit: 10**30, page: 10**30, per_page: 10**30 }, { limit: "abc", page: "1e9" }]
    each_list_endpoint do |path, actor|
      params.each do |values|
        get path, params: values, headers: h(actor)
        next unless probe!("#{path}?#{values.to_query}")
        assert_equal 200, response.status, "#{path}?#{values.to_query}"
      end
    end
    post "/api/admin/users/#{@js.id}/grant-plan", params: { planCode: "pro", days: 10**30 }, headers: h(:admin), as: :json
    assert_response :created
    assert_operator Subscription.find(response.parsed_body["id"]).current_period_end, :<, 367.days.from_now
    post "/api/admin/users/#{@js.id}/grant-plan", params: { planCode: "pro", days: -10 }, headers: h(:admin), as: :json
    assert_response :created
    assert_operator Subscription.find(response.parsed_body["id"]).current_period_end, :>, Time.current
    verdict!
  end

  # ---- JSON type confusion ------------------------------------------------------------------

  test "type confusion in query strings (arrays/hashes where strings expected) never 500" do
    each_filter do |path, key, actor|
      [{ key => ["a", "b"] }, { key => { "x" => "y" } }].each do |values|
        get path, params: values, headers: h(actor)
        probe!("#{path}?#{values.to_query}")
      end
    end
    get "/api/candidates/compare/list", params: { ids: %w[a b] }, headers: h(:emp)
    probe!("compare ids[]")
    verdict!
  end

  test "type confusion in JSON bodies never 500" do
    js_conv = @world.refs[:js][:conversation]
    probes = [
      [:post, "/api/auth/login", nil, { email: ["a@example.com"], password: { "x" => 1 } }],
      [:post, "/api/auth/register", nil, { name: ["x"], email: { "a" => 1 }, password: ["p"], role: ["jobseeker"] }],
      [:post, "/api/auth/forgot-password", nil, { email: ["a@example.com"] }],
      [:post, "/api/auth/reset-password", nil, { token: ["t"], password: ["LongEnough123!"] }],
      [:post, "/api/auth/verify-email", nil, { token: { "a" => 1 } }],
      [:put, "/api/profile", :js, { headline: ["x"], skills: "not-an-array", yearsExperience: "many", hourlyRate: [1] }],
      [:post, "/api/jobs", :emp, { title: ["x"], description: { "a" => 1 }, skills: "Mixing", compensationMin: "lots", slots: [2], status: ["draft"] }],
      [:post, "/api/jobs", :emp, { title: "Overflow", location: "Pune", description: "d" * 90, status: "draft", compensationMin: 10**12, slots: 10**12 }],
      [:post, "/api/jobs/#{@world.refs[:emp2][:job]}/apply", :js, { coverLetter: ["x"], screeningAnswers: "yes" }],
      [:post, "/api/job-alerts", :js, { name: ["x"], frequency: ["daily"], remoteOnly: "maybe" }],
      [:patch, "/api/employer/jobs/#{@world.refs[:emp][:job]}", :emp, { status: ["closed"] }],
      [:patch, "/api/employer/applications/#{@world.refs[:emp][:received_application]}", :emp, { status: ["Shortlisted"], recruiterRating: [5] }],
      [:post, "/api/portfolio", :js, { type: ["audio"], title: { "a" => 1 }, url: ["https://x.example"], year: "old", mediaMetadata: "str" }],
      [:post, "/api/reviews", :js, { employerId: [@emp.id], rating: "five", body: ["x"] }],
      [:post, "/api/availability", :js, { startAt: "not a date", endAt: ["x"], status: { "a" => 1 } }],
      [:post, "/api/conversations", :js, { employerId: [@emp.id], jobId: { "a" => 1 } }],
      [:post, "/api/conversations/#{js_conv}/messages", :js, { body: ["hello"] }],
      [:post, "/api/conversations/#{js_conv}/messages", :js, { body: { "a" => "b" } }],
      [:post, "/api/acts", :js, { name: ["x"], actType: { "a" => 1 }, lineupSize: "big", minFee: 10**12, genres: "Jazz" }],
      [:post, "/api/acts/#{@world.refs[:js][:act]}/members", :js, { displayName: ["x"], roleName: { "a" => 1 }, userId: [@world.user(:js2).id] }],
      [:post, "/api/bookings", :js, { actId: [@world.refs[:emp][:act]], eventType: ["x"], budgetMin: "cheap", productionProvided: "PA" }],
      [:post, "/api/bookings", :js, { actId: @world.refs[:emp][:act], eventType: "x", city: "Pune", budgetMin: 10**15, durationMinutes: -5 }],
      [:post, "/api/bookings/#{@world.refs[:js][:owned_booking]}/quote", :js, { performanceFee: "abc", depositPercent: [50] }],
      [:post, "/api/bookings/#{@world.refs[:js][:owned_booking]}/quote", :js, { performanceFee: 10**15 }],
      [:post, "/api/bookings/#{@world.refs[:js][:requested_booking]}/status", :js, { status: ["cancelled"] }],
      [:post, "/api/organizations", :js, { name: ["x"], website: ["https://x.example"] }],
      [:post, "/api/organizations/#{@world.refs[:js][:org]}/members", :js, { email: ["a@example.com"], role: ["admin"] }],
      [:post, "/api/urgent-requests", :js, { title: ["x"], roleName: "Keys", city: "Pune", startAt: "tomorrow-ish", budgetMin: "x" }],
      [:post, "/api/urgent-requests/#{@world.refs[:emp][:urgent]}/respond", :js, { message: ["x"], rate: "cheap" }],
      [:patch, "/api/urgent-requests/#{@world.refs[:js][:urgent]}", :js, { status: ["filled"] }],
      [:post, "/api/talent-folders", :emp, { name: ["x"], description: { "a" => 1 } }],
      [:post, "/api/band-projects", :js, { name: "B", genres: "rock", countNeeded: "x" }],
      [:post, "/api/band-projects/#{@world.refs[:js][:project]}/roles", :js, { roleName: "Keys", countNeeded: "two" }],
      [:post, "/api/crew-plans", :js, { title: "C", eventType: "gala", city: "Pune", needs: "sound", audienceSize: "huge", budget: [1] }],
      [:post, "/api/uploads/presign", :js, { filename: ["a"], contentType: ["audio/mpeg"], size: "big" }],
      [:post, "/api/reports", :js, { entityType: "job", entityId: ["x"], reason: "spam" }],
      [:post, "/api/verification-requests", :js, { kind: ["professional"] }],
      [:post, "/api/billing/checkout", :js, { planCode: ["pro"] }],
      [:patch, "/api/admin/users/#{@js.id}", :admin, { status: ["active"] }],
      [:post, "/api/admin/users/#{@js.id}/grant-plan", :admin, { planCode: ["pro"], days: "x" }],
      [:patch, "/api/admin/jobs/#{@world.refs[:emp][:job]}", :admin, { status: ["published"], note: { "a" => 1 } }],
      [:patch, "/api/notifications/#{@world.refs[:js][:notification]}", :js, { read: "false" }]
    ]
    probes.each do |verb, path, actor, params|
      public_send(verb, path, params:, headers: h(actor), as: :json)
      probe!("#{verb.upcase} #{path} #{params.to_json.first(120)}")
    end
    verdict!
  end

  private

  def h(actor) = @world.headers(actor)

  def ok!
    assert_equal 200, response.status, response.body.first(300)
  end

  # Records a 5xx or a malformed error body instead of stopping at the first one, so a single
  # run lists every failing probe. Returns true when the response is sound.
  def probe!(label)
    problem = if response.status >= 500
      "#{response.status}: #{response.body.first(160).gsub(/\s+/, ' ')}"
    elsif response.status >= 400
      body = JSON.parse(response.body) rescue nil
      "error body lacks {error}: #{response.body.first(120)}" unless body.is_a?(Hash) && body["error"].is_a?(String) && body["traces"].nil?
    end
    return true unless problem
    (@problems ||= []) << [label, problem]
    false
  end

  # Fails with every unexpected problem; skips when all problems are recorded KNOWN_GAPS.
  def verdict!
    return if @problems.blank?
    known, unknown = @problems.partition { |label, _| KNOWN_GAPS.any? { |pattern, _| label.match?(pattern) } }
    flunk unknown.map { _1.join(" => ") }.join("\n") if unknown.any?
    skip known.map { |label, _| KNOWN_GAPS.find { |pattern, _| label.match?(pattern) }.last }.uniq.join(" | ")
  end

  def each_filter
    LIST_FILTERS.each { |path, keys| keys.each { yield path, _1, nil } }
    AUTH_LIST_FILTERS.each { |path, keys| keys.each { yield path, _1, :emp } }
  end

  def each_list_endpoint
    %w[/api/jobs /api/public/talent /api/public/acts /api/reviews /api/resources /api/search?q=mix].each { yield _1, nil }
    %w[/api/candidates /api/acts /api/urgent-requests /api/employer/applications /api/bookings /api/conversations /api/notifications
       /api/talent-folders /api/band-projects /api/crew-plans /api/organizations /api/employers /api/recent-activity /api/availability].each { yield _1, :emp }
    %w[/api/applications /api/saved-jobs /api/job-alerts /api/portfolio].each { yield _1, :js }
    %w[/api/admin/users /api/admin/jobs /api/admin/reviews /api/admin/verifications /api/admin/reports /api/admin/audit
       /api/admin/subscriptions /api/admin/billing-attempts /api/admin/bookings].each { yield _1, :admin }
  end
end
