require "test_helper"
require_relative "../support/api_matrix_world"

# SQL query budget and list bounds for every GET list endpoint.
#
# Each endpoint is measured on the base matrix world and again after GROWTH more rows of every
# kind were added for the viewer. A query count that grows with the row count is an N+1; a list
# whose main SELECT carries no LIMIT is unbounded. Set API_MATRIX_REPORT=1 to print the table.
class ApiQueryBudgetTest < ActionDispatch::IntegrationTest
  include ApiMatrixAssertions

  GROWTH = 8
  ABSOLUTE_BUDGET = 20

  # path, actor, main table (for the LIMIT check)
  LISTS = [
    ["/api/jobs", nil, "jobs"], ["/api/jobs", :js, "jobs"], ["/api/saved-jobs", :js, "jobs"], ["/api/applications", :js, "applications"],
    ["/api/job-alerts", :js, "job_alerts"], ["/api/employer/applications", :emp, "applications"], ["/api/portfolio", :js, "portfolio_items"],
    ["/api/notifications", :js, "notifications"], ["/api/reviews", :js, "reviews"], ["/api/resources", nil, "career_resources"],
    ["/api/dashboard", :js, "jobs"], ["/api/dashboard", :emp, "jobs"], ["/api/search?q=Matrix", nil, "jobs"],
    ["/api/public/talent", nil, "users"], ["/api/candidates", :emp, "users"], ["/api/recent-activity", :emp, "recent_activities"],
    ["/api/employers", :js, "users"], ["/api/availability", :js, "availability_windows"], ["/api/conversations", :js, "conversations"],
    ["/api/conversations/{conversation}/messages", :js, "messages"], ["/api/public/acts", nil, "acts"], ["/api/acts", :emp, "acts"],
    ["/api/acts/me", :js, "acts"], ["/api/bookings", :js, "booking_requests"], ["/api/bookings/{requested_booking}/payments", :js, "booking_payments"],
    ["/api/organizations", :js, "organizations"], ["/api/organizations/{org}/members", :js, "organization_members"],
    ["/api/urgent-requests", :js, "urgent_requests"], ["/api/urgent-requests/{urgent}/responses", :js, "urgent_request_responses"],
    ["/api/talent-folders", :emp, "talent_folders"], ["/api/talent-folders/{folder}", :emp, "talent_folder_members"],
    ["/api/band-projects", :js, "band_projects"], ["/api/crew-plans", :js, "crew_plans"],
    ["/api/admin/users", :admin, "users"], ["/api/admin/jobs", :admin, "jobs"], ["/api/admin/reviews", :admin, "reviews"],
    ["/api/admin/verifications", :admin, "verification_requests"], ["/api/admin/reports", :admin, "reports"], ["/api/admin/audit", :admin, "audit_logs"],
    ["/api/admin/subscriptions", :admin, "subscriptions"], ["/api/admin/billing-attempts", :admin, "billing_attempts"], ["/api/admin/bookings", :admin, "booking_requests"],
    ["/api/admin/billing-events", :admin, "billing_events"], ["/api/admin/demo-data", :admin, "audit_logs"]
  ].freeze

  N_PLUS_ONE = {
    "/api/talent-folders" => "OWNER: talent-folders — per-folder talent_folder_members.count (talent_folders_controller.rb:3)"
  }.freeze

  UNBOUNDED = {
    "/api/saved-jobs" => "OWNER: jobs — jobs_controller.rb:60 returns every saved job",
    "/api/applications" => "OWNER: applications — applications_controller.rb:4 returns every application",
    "/api/job-alerts" => "OWNER: job-alerts — job_alerts_controller.rb:4 returns every alert",
    "/api/employer/applications" => "OWNER: employer-applications — employer/applications_controller.rb:5 returns every application (with candidate emails)",
    "/api/reviews" => "OWNER: reviews — reviews_controller.rb:5 returns every published review",
    "/api/resources" => "OWNER: resources — resources_controller.rb:2 returns every published resource",
    "/api/employers" => "OWNER: talent — talent_controller.rb:76 returns every active employer to any signed-in user",
    "/api/conversations" => "OWNER: messaging — conversations_controller.rb:11 returns every conversation",
    "/api/bookings/{requested_booking}/payments" => "OWNER: bookings — bookings_controller.rb:137 returns every payment of a booking",
    "/api/talent-folders" => "OWNER: talent-folders — talent_folders_controller.rb:3",
    "/api/talent-folders/{folder}" => "OWNER: talent-folders — talent_folders_controller.rb:10 returns every member",
    "/api/crew-plans" => "OWNER: crew-plans — crew_plans_controller.rb:4",
  }.freeze

  test "list endpoints stay within the query budget and do not grow with rows (no N+1)" do
    world = ApiMatrixWorld.build
    base = measure(world)
    grow(world, GROWTH)
    grown = measure(world)
    rows = LISTS.map { |path, actor, _| [path, actor, base.fetch([path, actor]), grown.fetch([path, actor])] }
    print_table(rows) if ENV["API_MATRIX_REPORT"]
    failures = rows.filter_map do |path, actor, (before, _), (after, _)|
      next if N_PLUS_ONE.key?(path)
      "#{path} as #{actor || 'anonymous'}: #{before} -> #{after} queries" if after - before > 2 || after > ABSOLUTE_BUDGET
    end
    assert_empty failures, "query count grows with rows (N+1) or exceeds #{ABSOLUTE_BUDGET}"
    known = rows.select { |path, _, (before, _), (after, _)| N_PLUS_ONE[path] && after - before > 2 }
    skip known.map { N_PLUS_ONE[_1.first] }.uniq.join(" | ") if known.any?
  end

  test "list endpoints bound their main SELECT with LIMIT" do
    world = ApiMatrixWorld.build
    unbounded = LISTS.filter_map do |path, actor, table|
      sqls = capture_sql { get world.path(path, actor || :js), headers: world.headers(actor) }
      assert_equal 200, response.status, path
      # The listing query: a SELECT from the table that is not a count, an existence check or a
      # primary-key lookup (e.g. the current user). Bounded when it ends with a top-level LIMIT.
      main = sqls.select do |sql|
        sql.match?(/\ASELECT .*\bFROM "#{table}"/m) && !sql.match?(/\ASELECT (COUNT|1 AS one)/i) &&
          !sql.match?(/WHERE "#{table}"\."(id|user_id)" = \$\d+ LIMIT/)
      end
      next if main.empty? || main.any? { _1.match?(/\bLIMIT \$?\d+( OFFSET \$?\d+)?\s*\z/) }
      path
    end.uniq
    unexpected = unbounded - UNBOUNDED.keys
    assert_empty unexpected, "new unbounded list endpoints"
    skip unbounded.map { UNBOUNDED[_1] }.join(" | ") if unbounded.any?
  end

  private

  def measure(world)
    LISTS.to_h do |path, actor, _|
      resolved = world.path(path, actor || :js)
      get resolved, headers: world.headers(actor) # warm-up (schema, prepared statements)
      # The transactional test connection keeps its query cache across requests; without this
      # the measured request would be served from the warm-up's cache.
      ActiveRecord::Base.connection.clear_query_cache
      count = ApiMatrixWorld.count_queries { get resolved, headers: world.headers(actor) }
      assert_equal 200, response.status, "#{resolved}: #{response.body.first(200)}"
      [[path, actor], [count, parsed_json(path).to_s.length]]
    end
  end

  def capture_sql
    sqls = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { sqls << payload[:sql] unless payload[:name] == "SCHEMA" }, "sql.active_record") { yield }
    sqls
  end

  # Adds `n` more of every row kind the :js / :emp viewers can see.
  def grow(world, n)
    js = world.user(:js)
    emp = world.user(:emp)
    admin = world.user(:admin)
    n.times do |i|
      employer = User.create!(name: "Grow Employer #{i}", email: "grow-emp-#{i}@example.com", password: ApiMatrixWorld::PASSWORD, role: "employer", status: "active", profile_complete: true)
      employer.create_profile!(company_name: "Grow #{i}", verified: i.even?)
      artist = User.create!(name: "Grow Artist #{i}", email: "grow-js-#{i}@example.com", password: ApiMatrixWorld::PASSWORD, role: "jobseeker", status: "active", profile_complete: true)
      artist.create_profile!(headline: "Matrix grower #{i}", skills: ["Mixing"])
      job = ApiMatrixWorld.create_job(emp, "published")
      other_job = ApiMatrixWorld.create_job(employer, "published")
      Application.create!(job:, candidate: js, status: "Applied")
      Application.create!(job:, candidate: artist, status: "Hired")
      SavedJob.create!(user: js, job: other_job)
      JobAlert.create!(user: js, name: "Grow #{i}", frequency: "daily")
      PortfolioItem.create!(user: js, kind: "audio", title: "Matrix grow #{i}", url: "https://example.com/#{i}.mp3", visibility: "public")
      Notification.create!(user: js, kind: "system", title: "Grow #{i}")
      AvailabilityWindow.create!(user: js, start_at: (i + 5).days.from_now, end_at: (i + 6).days.from_now, status: "available")
      act = Act.create!(owner: js, name: "Matrix grow act #{i}", act_type: "band", status: "active", currency: "INR", fee_basis: "event")
      act.act_members.create!(display_name: "M#{i}", role_name: "Keys", member_status: "confirmed")
      other_act = Act.create!(owner: employer, name: "Grow act #{i}", act_type: "band", status: "active", currency: "INR", fee_basis: "event")
      other_act.act_members.create!(user: employer, display_name: employer.name, role_name: "Lead", is_leader: true, member_status: "confirmed")
      booking = BookingRequest.create!(act: other_act, requester: js, event_type: "wedding", city: "Pune", currency: "INR", status: "quoted")
      quote = booking.booking_quotes.create!(created_by: employer, performance_fee: 100, currency: "INR", status: "sent")
      booking.booking_payments.create!(booking_quote: quote, payer: js, kind: "deposit", amount: 50, currency: "INR", provider: "internal", status: "paid")
      BookingRequest.find(world.refs[:js][:requested_booking]).booking_payments.create!(payer: js, kind: "balance", amount: 10 + i, currency: "INR", provider: "internal", status: "failed")
      conversation = Conversation.create!(candidate: js, employer:, job: other_job)
      conversation.messages.create!(sender: employer, body: "Grow #{i}")
      Conversation.find(world.refs[:js][:conversation]).messages.create!(sender: emp, body: "More #{i}")
      org = Organization.create!(owner: employer, name: "Grow org #{i}", status: "active")
      org.organization_members.create!(user: employer, role: "owner")
      org.organization_members.create!(user: js, role: "member")
      Organization.find(world.refs[:js][:org]).organization_members.create!(user: artist, role: "member")
      urgent = UrgentRequest.create!(requester: employer, title: "Grow urgent #{i}", role_name: "Drummer", city: "Pune", start_at: 2.days.from_now, currency: "INR", status: "open")
      UrgentRequestResponse.create!(urgent_request: urgent, user: artist, status: "available")
      UrgentRequestResponse.create!(urgent_request_id: world.refs[:js][:urgent], user: artist, status: "available")
      folder = TalentFolder.create!(owner: emp, name: "Grow folder #{i}")
      folder.talent_folder_members.create!(candidate: artist)
      TalentFolder.find(world.refs[:emp][:folder]).talent_folder_members.create!(candidate: artist)
      project = BandProject.create!(owner: js, name: "Grow band #{i}", status: "open")
      project.band_project_roles.create!(role_name: "Keys", status: "open")
      plan = CrewPlan.create!(owner: js, title: "Grow plan #{i}", event_type: "gala", city: "Pune", currency: "INR")
      plan.crew_plan_roles.create!(category: "Audio", role_name: "FOH", priority: "required")
      Review.create!(author: artist, employer: emp, rating: 5, body: "Grow review", status: "published")
      VerificationRequest.create!(user: artist, kind: "professional")
      Report.create!(reporter: artist, entity_type: "job", entity_id: job.id, reason: "grow", status: "open")
      AuditLog.create!(actor: artist, action: "grow")
      Subscription.create!(user: employer, plan_code: "pro", provider: "internal", status: "active")
      BillingAttempt.create!(user: employer, operation: "subscription_create", provider: "razorpay", idempotency_key: "grow-#{i}-#{SecureRandom.hex(3)}", state: "pending")
      RecentActivity.create!(user: emp, kind: "profile_view", entity_id: artist.id, label: artist.name)
      CareerResource.create!(title: "Grow #{i}", category: "live", status: "published", description: "x")
      BillingEvent.create!(provider: "razorpay", provider_event_id: "evt_grow_#{i}", event_type: "payment.captured", user: employer, processed_at: Time.current, payload: {})
      SyntheticQa::DemoJobs.record!(SecureRandom.uuid, "succeeded", actor_id: admin.id, kind: "seed", batch: "demo-grow-#{i}", size: "small")
      User.create!(name: "Demo grow #{i}", email: "demo-grow-#{i}@example.com", password: ApiMatrixWorld::PASSWORD, role: "jobseeker", status: "active", synthetic_batch: "demo-grow-#{i}")
      AvailabilityWindow.create!(user: admin, start_at: 1.day.from_now, end_at: 2.days.from_now) if i.zero?
    end
  end

  def print_table(rows)
    puts "\n#{'endpoint'.ljust(48)} #{'viewer'.ljust(9)} base  +#{GROWTH}rows  bytes(+#{GROWTH})  flag"
    rows.each do |path, actor, (before, _), (after, bytes)|
      flag = [("N+1" if after - before > 2), (">#{ABSOLUTE_BUDGET}" if after > ABSOLUTE_BUDGET), ("unbounded" if UNBOUNDED.key?(path))].compact.join(",")
      puts "#{path.ljust(48)} #{(actor || 'anon').to_s.ljust(9)} #{before.to_s.rjust(4)}  #{after.to_s.rjust(7)}  #{bytes.to_s.rjust(11)}  #{flag}"
    end
  end
end
