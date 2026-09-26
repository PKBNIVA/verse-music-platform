require "test_helper"
require "minitest/mock"

class AuthHardeningTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "StrongPass123!".freeze
  PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send", "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze
  NO_PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => nil, "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(name: "Throttle Target", email: "target@example.com", password: PASSWORD, role: "jobseeker", status: "active")
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "failed logins are throttled per email and IP even with the correct password afterwards" do
    AuthController::LOGIN_FAILURES_PER_EMAIL_AND_IP.times do
      login("target@example.com", "wrong-password", ip: "198.51.100.1")
      assert_response :unauthorized
    end

    login(" TARGET@example.com ", PASSWORD, ip: "198.51.100.1")
    assert_response :too_many_requests
    assert_equal "Too many requests. Try again later.", response.parsed_body["error"]

    User.create!(name: "Other", email: "other@example.com", password: PASSWORD, role: "jobseeker", status: "active")
    login("other@example.com", PASSWORD, ip: "198.51.100.1")
    assert_response :success
  end

  test "an attacker exhausting their email and IP budget does not lock out the real user elsewhere" do
    (AuthController::LOGIN_FAILURES_PER_EMAIL_AND_IP + 5).times do
      login("target@example.com", "wrong-password", ip: "198.51.100.66")
    end
    assert_response :too_many_requests

    login("target@example.com", PASSWORD, ip: "192.0.2.10")
    assert_response :success
  end

  test "global per-email budget stops distributed guessing and resets after the window" do
    AuthController::LOGIN_FAILURES_PER_EMAIL.times do |index|
      login("target@example.com", "wrong-password", ip: "10.0.#{index / 200}.#{index % 200 + 1}")
      assert_response :unauthorized
    end
    login("target@example.com", PASSWORD, ip: "192.0.2.10")
    assert_response :too_many_requests

    travel AuthController::LOGIN_FAILURE_PERIOD + 1.second do
      login("target@example.com", PASSWORD, ip: "192.0.2.10")
      assert_response :success
    end
  end

  test "successful logins do not consume the login budget" do
    (AuthController::LOGIN_FAILURES_PER_IP + 5).times do
      login("target@example.com", PASSWORD)
      assert_response :success
    end
  end

  test "an IP is throttled after many failures across different emails" do
    AuthController::LOGIN_FAILURES_PER_IP.times do |index|
      login("missing-#{index}@example.com", "wrong-password", ip: "203.0.113.9")
      assert_response :unauthorized
    end

    login("target@example.com", PASSWORD, ip: "203.0.113.9")
    assert_response :too_many_requests

    login("target@example.com", PASSWORD, ip: "203.0.113.10")
    assert_response :success
  end

  test "throttle cache keys do not contain the email address" do
    login("target@example.com", "wrong-password")
    keys = Rails.cache.instance_variable_get(:@data).keys
    assert keys.any? { _1.start_with?("rate:login-failure:email:") }
    assert keys.none? { _1.include?("target@example.com") }
  end

  test "a user keeps up to ten live sessions" do
    12.times { login("target@example.com", PASSWORD) }
    assert_equal AuthController::MAX_LIVE_SESSIONS, @user.sessions.count
    assert_equal 10, AuthController::MAX_LIVE_SESSIONS
  end

  test "setting a user to pending or suspended revokes their sessions" do
    admin = User.create!(name: "Admin", email: "admin-hardening@example.com", password: PASSWORD, role: "admin", status: "active")
    admin_token = login_token(admin.email)

    %w[pending suspended].each do |status|
      @user.reload.update!(status: "active")
      user_token = login_token(@user.email)
      patch "/api/admin/users/#{@user.id}", params: { status: }, headers: auth(admin_token), as: :json
      assert_response :success
      assert_equal 0, @user.sessions.count, "expected #{status} to revoke sessions"
      get "/api/me", headers: auth(user_token)
      assert_response :unauthorized
    end

    @user.reload.update!(status: "active")
    login_token(@user.email)
    patch "/api/admin/users/#{@user.id}", params: { status: "active" }, headers: auth(admin_token), as: :json
    assert_response :success
    assert_equal 1, @user.sessions.count
  end

  test "registration queues the verification email and reports it as queued" do
    with_env(PROVIDER_ENV.merge("FRONTEND_URL" => "https://verse.example//")) do
      assert_enqueued_jobs 1, only: EmailDeliveryJob do
        post "/api/auth/register", params: { name: "Queued", email: "queued@example.com", password: PASSWORD, role: "jobseeker" }, as: :json
      end
    end
    assert_response :created
    assert_equal({ "queued" => true }, response.parsed_body["verificationDelivery"])

    job = enqueued_jobs.find { _1[:job] == EmailDeliveryJob }
    user_id, template, sealed = ActiveJob::Arguments.deserialize(job[:args])
    assert_equal User.find_by!(email: "queued@example.com").id, user_id
    assert_equal "verify_email", template
    link = EmailDeliveryJob.unseal(sealed)
    assert_match %r{\Ahttps://verse\.example/verify-email\?token=.+}, link
    token = Rack::Utils.parse_query(URI.parse(link).query).fetch("token")
    assert_not_includes job[:args].to_json, token
    assert_not_includes job[:args].to_json, "queued@example.com"
  end

  test "verification request keeps debugLink outside production and reports unconfigured delivery" do
    token = login_token(@user.email)
    with_env(NO_PROVIDER_ENV.merge("FRONTEND_URL" => "https://verse.example/")) do
      assert_no_enqueued_jobs do
        post "/api/auth/request-email-verification", params: {}, headers: auth(token), as: :json
      end
    end
    assert_response :success
    assert_match %r{\Ahttps://verse\.example/verify-email\?token=}, response.parsed_body.fetch("debugLink")
    assert_equal({ "queued" => false, "delivered" => false, "reason" => "Email provider not configured" }, response.parsed_body["delivery"])
  end

  test "forgot password queues delivery without changing the generic response" do
    with_env(PROVIDER_ENV) do
      assert_enqueued_with(job: EmailDeliveryJob) do
        post "/api/auth/forgot-password", params: { email: "target@example.com" }, as: :json
      end
    end
    assert_response :success
    known = response.parsed_body

    with_env(PROVIDER_ENV) do
      assert_no_enqueued_jobs { post "/api/auth/forgot-password", params: { email: "nobody@example.com" }, as: :json }
    end
    assert_equal known, response.parsed_body
    assert_nil known["debugLink"]
  end

  test "registration still succeeds when the email job cannot be enqueued" do
    failing_enqueue = ->(**) { raise ActiveRecord::ConnectionNotEstablished, "queue down" }
    with_env(PROVIDER_ENV) do
      EmailDeliveryJob.stub(:enqueue, failing_enqueue) do
        post "/api/auth/register", params: { name: "No Queue", email: "no-queue@example.com", password: PASSWORD, role: "jobseeker" }, as: :json
      end
    end
    assert_response :created
    assert_equal({ "queued" => false, "delivered" => false, "reason" => "delivery error" }, response.parsed_body["verificationDelivery"])
  end

  test "forgot password logs a warning without email or token when no provider is configured" do
    log = capture_log do
      with_env(NO_PROVIDER_ENV) do
        assert_no_enqueued_jobs { post "/api/auth/forgot-password", params: { email: "target@example.com" }, as: :json }
      end
    end
    assert_response :success
    assert_equal "If an account exists, password reset instructions have been sent.", response.parsed_body["message"]

    warning = log.lines.find { _1.include?("password_reset_email_skipped") }
    assert warning, "expected a password reset warning in:\n#{log}"
    assert_includes warning, "WARN"
    assert_includes warning, "Email provider not configured"
    assert_not_includes log, "target@example.com"
    assert_no_match(/token=/, log)
  end

  test "production link building falls back to the public frontend and logs an error" do
    controller = AuthController.new
    production = ActiveSupport::EnvironmentInquirer.new("production")
    log = capture_log do
      with_env("FRONTEND_URL" => nil) do
        Rails.stub(:env, production) { assert_equal "https://verse-music-platform.vercel.app", controller.send(:frontend_url) }
      end
    end
    assert_includes log, "frontend_url_missing"

    with_env("FRONTEND_URL" => "https://app.verse.example///") do
      Rails.stub(:env, production) { assert_equal "https://app.verse.example", controller.send(:frontend_url) }
    end
    with_env("FRONTEND_URL" => nil) { assert_equal "http://localhost:5173", controller.send(:frontend_url) }
  end

  test "sensitive parameters are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("email" => "a@example.com", "razorpay_signature" => "sig", "otp" => "123456", "password" => "x", "name" => "Visible")
    assert_equal "Visible", filtered["name"]
    %w[email razorpay_signature otp password].each { assert_equal "[FILTERED]", filtered[_1] }
  end

  private

  def login(email, password, ip: "127.0.0.1")
    post "/api/auth/login", params: { email:, password: }, env: { "REMOTE_ADDR" => ip }, as: :json
  end

  def login_token(email)
    login(email, PASSWORD)
    assert_response :success
    response.parsed_body.fetch("accessToken")
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io).tap { _1.formatter = ->(severity, _time, _prog, message) { "#{severity} #{message}\n" } }
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
