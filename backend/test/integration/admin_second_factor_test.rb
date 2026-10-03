require "test_helper"
require "minitest/mock"

# Admin password sign-in is two steps: the password answers with a short-lived
# challenge, and a code emailed to the admin completes it.
class AdminSecondFactorTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "StrongPass123!".freeze
  PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send", "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze
  NO_PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => nil, "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @admin = User.create!(name: "Two Step Admin", email: "two-step@example.com", password: PASSWORD, role: "admin", status: "active")
    @member = User.create!(name: "Plain Member", email: "member@example.com", password: PASSWORD, role: "employer", status: "active", email_verified: true)
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "an admin password gives a challenge, not a session, and the emailed code completes it" do
    challenge = with_env(PROVIDER_ENV) do
      assert_enqueued_jobs 1, only: EmailDeliveryJob do
        password_login(@admin.email)
      end
      assert_response :accepted
      response.parsed_body
    end
    assert_equal true, challenge["secondFactorRequired"]
    assert_equal "email_code", challenge["method"]
    assert_equal 600, challenge["expiresIn"]
    assert_nil challenge["accessToken"]
    assert_nil challenge["user"]
    assert_nil challenge["debugCode"], "a configured provider never gets an on-screen code"
    assert_equal 0, @admin.sessions.count
    assert_nil @admin.reload.last_login_at

    job = enqueued_jobs.find { _1[:job] == EmailDeliveryJob }
    user_id, template, sealed = ActiveJob::Arguments.deserialize(job[:args])
    assert_equal [@admin.id, "sign_in_code"], [user_id, template]
    code = EmailDeliveryJob.unseal(sealed)
    assert_not_includes challenge["challengeToken"], code

    complete(challenge["challengeToken"], code)
    assert_response :success
    assert_equal %w[accessToken realtime user], response.parsed_body.keys.sort # realtime: R2 live updates
    assert_equal @admin.id, response.parsed_body.dig("user", "id")
    assert @admin.reload.last_login_at
    assert_equal({ "method" => "password", "secondFactor" => "email_code" }, AuditLog.where(action: "auth.login").last.metadata)

    get "/api/admin/stats", headers: bearer(response.parsed_body["accessToken"])
    assert_response :success

    complete(challenge["challengeToken"], code)
    assert_response :unauthorized, "the code is single-use"
  end

  test "non-admin password sign-in and admin email-code sign-in are unchanged" do
    with_env(NO_PROVIDER_ENV) { password_login(@member.email) }
    assert_response :success
    assert response.parsed_body["accessToken"]
    with_env(PROVIDER_ENV) { password_login(@member.email) }
    assert_response :success
    assert response.parsed_body["accessToken"]

    with_env(NO_PROVIDER_ENV) { post "/api/auth/otp/request", params: { email: @admin.email }, as: :json }
    code = response.parsed_body.fetch("debugCode")
    post "/api/auth/otp/verify", params: { email: @admin.email, code: }, as: :json
    assert_response :success
    assert response.parsed_body["accessToken"], "an emailed code already proves inbox control"
  end

  test "wrong codes, a forged or expired challenge, and a wrong password all fail" do
    password_login(@admin.email, "wrong-password")
    assert_response :unauthorized
    assert_nil response.parsed_body["challengeToken"]

    token, code = challenge_for(@admin)
    complete(token, code == "000000" ? "111111" : "000000")
    assert_response :unauthorized
    assert_equal "OTP_INVALID", response.parsed_body["code"]

    complete(token.sub(/.\z/) { _1 == "a" ? "b" : "a" }, code)
    assert_response :unauthorized
    assert_equal "SECOND_FACTOR_EXPIRED", response.parsed_body["code"]

    travel SignInCode::LIFETIME + 1.second do
      complete(token, code)
      assert_response :unauthorized
      assert_equal "SECOND_FACTOR_EXPIRED", response.parsed_body["code"]
    end
    assert_equal 0, @admin.sessions.count
  end

  test "a challenge for one admin cannot be completed with a code sent to another address" do
    token, _code = challenge_for(@admin)
    with_env(NO_PROVIDER_ENV) { post "/api/auth/otp/request", params: { email: @member.email }, as: :json }
    other_code = response.parsed_body.fetch("debugCode")
    complete(token, other_code)
    assert_response :unauthorized
    assert_equal 0, @admin.sessions.count
  end

  test "the code is locked after five wrong guesses and a newer challenge replaces an older one" do
    token, code = challenge_for(@admin)
    wrong = code == "111111" ? "222222" : "111111"
    SignInCode::MAX_ATTEMPTS.times { complete(token, wrong) }
    complete(token, code)
    assert_response :unauthorized, "the right code no longer works once attempts are spent"

    old_token, old_code = challenge_for(@admin)
    new_token, new_code = challenge_for(@admin)
    complete(old_token, old_code)
    assert_response :unauthorized
    complete(new_token, new_code)
    assert_response :success
  end

  test "challenges and wrong guesses are throttled" do
    AuthController::SECOND_FACTOR_CHALLENGES_PER_EMAIL.times do
      password_login(@admin.email)
      assert_response :accepted
    end
    password_login(@admin.email)
    assert_response :too_many_requests

    Rails.cache.clear
    budget = AuthController::SECOND_FACTOR_FAILURES_PER_USER
    guesses = 0
    while guesses < budget
      token, code = challenge_for(@admin, ip: "198.51.100.#{guesses}")
      wrong = code == "111111" ? "222222" : "111111"
      [SignInCode::MAX_ATTEMPTS, budget - guesses].min.times do
        complete(token, wrong, ip: "203.0.113.#{guesses}")
        guesses += 1
      end
    end
    token, code = challenge_for(@admin, ip: "198.51.100.200")
    complete(token, code, ip: "203.0.113.250")
    assert_response :too_many_requests, "per-admin failure budget applies across addresses"
  end

  test "garbage challenge tokens fail from one address until the IP budget runs out" do
    AuthController::SECOND_FACTOR_FAILURES_PER_IP.times { complete("forged", "123456", ip: "192.0.2.50") }
    complete("forged", "123456", ip: "192.0.2.50")
    assert_response :too_many_requests
    [nil, 12, ["x"], "x" * 5000].each do |token|
      post "/api/auth/second-factor", params: { challengeToken: token, code: "123456" }, env: { "REMOTE_ADDR" => "192.0.2.51" }, as: :json
      assert_response :unauthorized
    end
  end

  test "auto (the default) requires the code when email can be delivered" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    [nil, "auto", "AUTO ", "something-else"].each do |mode|
      with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => mode)) do
        Rails.stub(:env, production) { password_login(@admin.email) }
      end
      assert_response :accepted, "mode #{mode.inspect}"
      assert response.parsed_body["challengeToken"]
      Rails.cache.clear
    end
    assert_equal 0, @admin.sessions.count
  end

  test "auto without email delivery in production lets the admin in, audits it and warns in the tester and doctor" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(NO_PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => nil)) do
      Rails.stub(:env, production) { password_login(@admin.email, ip: "198.51.100.9") }
      assert_response :success, "merging must never lock the owner out of admin"
      token = response.parsed_body.fetch("accessToken")
      skipped = AuditLog.where(action: "auth.admin_second_factor_skipped", entity_id: @admin.id).sole
      assert_equal({ "reason" => "email_delivery_not_configured", "ip" => "198.51.100.9" }, skipped.metadata)
      assert_equal({ "secondFactor" => "skipped" }, AuditLog.where(action: "auth.login").last.metadata)

      Rails.stub(:env, production) { get "/api/admin/tester", headers: bearer(token) }
      assert_response :success
      check = response.parsed_body["checks"].find { _1["name"] == "Admin 2-step sign-in" }
      assert_equal false, check["pass"]
      assert_match "Admin 2-step sign-in is off because email delivery is not configured", check["detail"]

      Rails.stub(:env, production) { get "/api/admin/users/lookup", params: { email: @admin.email }, headers: bearer(token) }
      assert_response :success
      note = response.parsed_body["diagnosis"].find { _1["code"] == "ADMIN_SECOND_FACTOR_SKIPPED" }
      assert_equal "warn", note["level"]
      assert_match "Admin 2-step sign-in is off because email delivery is not configured", note["message"]

      Rails.stub(:env, production) { get "/api/admin/users/lookup", params: { email: @member.email }, headers: bearer(token) }
      assert_nil response.parsed_body["diagnosis"].find { _1["code"].start_with?("ADMIN_SECOND_FACTOR") }, "only admin accounts get the note"

      Rails.stub(:env, production) { password_login(@member.email) }
      assert_response :success
      assert_equal 1, AuditLog.where(action: "auth.admin_second_factor_skipped").count, "members are never audited as skipped"
    end
  end

  test "a suppressed admin address counts as undeliverable: skipped under auto, refused under required" do
    EmailSuppression.create!(email: @admin.email, scope: "all", reason: "hard_bounce", last_event: "hard_bounce", last_event_at: Time.current, suppressed_at: Time.current)
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => nil)) do
      Rails.stub(:env, production) { password_login(@admin.email) }
      assert_response :success
      assert_equal "email_suppressed", AuditLog.where(action: "auth.admin_second_factor_skipped").sole.metadata["reason"]
      get "/api/admin/users/lookup", params: { email: @admin.email }, headers: bearer(response.parsed_body.fetch("accessToken"))
      note = response.parsed_body["diagnosis"].find { _1["code"] == "ADMIN_SECOND_FACTOR_SKIPPED" }
      assert_match "suppressed", note["message"]
    end
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "required")) do
      Rails.stub(:env, production) { password_login(@admin.email) }
      assert_response :service_unavailable
    end
  end

  test "an admin on a reserved domain (the seeded admin@musilynk.local) is never sent a code: skipped under auto, refused under required" do
    @admin.update!(email: "admin@musilynk.local")
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => nil)) do
      assert_no_enqueued_jobs(only: EmailDeliveryJob) { Rails.stub(:env, production) { password_login("admin@musilynk.local") } }
      assert_response :success, "a code sent to an address that can never receive mail would lock the owner out"
      assert_equal "email_address_undeliverable", AuditLog.where(action: "auth.admin_second_factor_skipped").sole.metadata["reason"]
      token = response.parsed_body.fetch("accessToken")

      Rails.stub(:env, production) { get "/api/admin/tester", headers: bearer(token) }
      check = response.parsed_body["checks"].find { _1["name"] == "Admin 2-step sign-in" }
      assert_equal false, check["pass"], "the tester flags any active admin whose address can't receive the code"
      assert_match "can't receive mail", check["detail"]

      Rails.stub(:env, production) { get "/api/admin/users/lookup", params: { email: "admin@musilynk.local" }, headers: bearer(token) }
      note = response.parsed_body["diagnosis"].find { _1["code"] == "ADMIN_SECOND_FACTOR_SKIPPED" }
      assert_match "can't receive mail", note["message"]
    end
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "required")) do
      Rails.stub(:env, production) { password_login("admin@musilynk.local") }
      assert_response :service_unavailable
    end
  end

  test "the tester reports the second step as on when it is enforced" do
    token = with_env("ADMIN_SECOND_FACTOR" => "off") { password_login(@admin.email) && response.parsed_body.fetch("accessToken") }
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "required")) { get "/api/admin/tester", headers: bearer(token) }
    check = response.parsed_body["checks"].find { _1["name"] == "Admin 2-step sign-in" }
    assert_equal true, check["pass"]
  end

  test "required without email delivery in production fails closed for admins only" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(NO_PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "required")) do
      Rails.stub(:env, production) { password_login(@admin.email) }
      assert_response :service_unavailable
      assert_equal "SECOND_FACTOR_UNAVAILABLE", response.parsed_body["code"]
      assert_nil response.parsed_body["accessToken"]
      assert_equal 0, @admin.sessions.count

      Rails.stub(:env, production) { password_login(@member.email) }
      assert_response :success
    end
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "required")) { password_login(@admin.email) }
    assert_response :accepted
  end

  test "ADMIN_SECOND_FACTOR=off is an explicit escape hatch, audited and flagged in the doctor" do
    with_env(PROVIDER_ENV.merge("ADMIN_SECOND_FACTOR" => "off")) do
      password_login(@admin.email)
      assert_response :success
      token = response.parsed_body.fetch("accessToken")
      assert_equal({ "secondFactor" => "disabled" }, AuditLog.where(action: "auth.login").last.metadata)
      get "/api/admin/users/lookup", params: { email: @admin.email }, headers: bearer(token)
      assert response.parsed_body["diagnosis"].any? { _1["code"] == "ADMIN_SECOND_FACTOR_OFF" }
    end
  end

  test "production never returns an on-screen code" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(PROVIDER_ENV) do
      Rails.stub(:env, production) { password_login(@admin.email) }
    end
    assert_response :accepted
    assert_nil response.parsed_body["debugCode"]
  end

  test "a suspended admin cannot complete a challenge issued before suspension" do
    token, code = challenge_for(@admin)
    @admin.update!(status: "suspended")
    complete(token, code)
    assert_response :forbidden
    assert_equal 0, @admin.sessions.count
  end

  private

  def password_login(email, password = PASSWORD, ip: "127.0.0.1")
    post "/api/auth/login", params: { email:, password: }, env: { "REMOTE_ADDR" => ip }, as: :json
  end

  def challenge_for(user, ip: "127.0.0.1")
    with_env(NO_PROVIDER_ENV) { password_login(user.email, ip:) }
    assert_response :accepted
    [response.parsed_body.fetch("challengeToken"), response.parsed_body.fetch("debugCode")]
  end

  def complete(token, code, ip: "127.0.0.1")
    post "/api/auth/second-factor", params: { challengeToken: token, code: }, env: { "REMOTE_ADDR" => ip }, as: :json
  end

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
