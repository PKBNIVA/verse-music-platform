require "test_helper"
require "minitest/mock"

class OtpAuthTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PASSWORD = "StrongPass123!".freeze
  PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send", "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze
  NO_PROVIDER_ENV = { "EMAIL_DELIVERY_WEBHOOK" => nil, "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil }.freeze

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(name: "Code User", email: "coder@example.com", password: PASSWORD, role: "employer", status: "active")
    @user.create_profile!
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "an existing account signs in with an emailed code and gets the login response shape" do
    code = request_code("Coder@Example.com ")
    assert_match(/\A\d{6}\z/, code)
    record = SignInCode.last
    assert_not_equal code, record.code_digest
    assert_not_includes record.code_digest, code
    assert_in_delta 10.minutes.from_now, record.expires_at, 5.seconds

    verify(" coder@example.com", code)
    assert_response :success
    body = response.parsed_body
    # `realtime`: whether the app should open the live-updates socket (R2).
    assert_equal %w[accessToken realtime user], body.keys.sort
    assert_equal @user.id, body.dig("user", "id")
    assert_equal true, body.dig("user", "emailVerified")
    assert @user.reload.email_verified?
    assert @user.last_login_at

    get "/api/me", headers: { "Authorization" => "Bearer #{body['accessToken']}" }
    assert_response :success
    assert_equal AuditLog.last.metadata, { "method" => "email_code" }
  end

  test "request responses are identical for known, unknown and sign-up addresses" do
    responses = with_env(PROVIDER_ENV) do
      %w[coder@example.com nobody@example.com].map do |email|
        post "/api/auth/otp/request", params: { email: }, env: { "REMOTE_ADDR" => "192.0.2.#{email.length}" }, as: :json
        assert_response :success
        response.parsed_body
      end.tap do |list|
        post "/api/auth/otp/request", params: { email: "newbie@example.com", name: "New Person", role: "jobseeker" }, env: { "REMOTE_ADDR" => "192.0.2.99" }, as: :json
        list << response.parsed_body
        # Sign-up details for an existing address are ignored, not an error.
        post "/api/auth/otp/request", params: { email: "coder@example.com", name: "Someone", role: "jobseeker" }, env: { "REMOTE_ADDR" => "192.0.2.98" }, as: :json
        list << response.parsed_body
      end
    end
    assert_equal 1, responses.uniq.size
    assert_nil responses.first["debugCode"], "debugCode must not be returned when a provider is configured"
    assert_equal %w[expiresIn message ok], responses.first.keys.sort
  end

  test "codes are emailed through the job with the code and recipient sealed" do
    with_env(PROVIDER_ENV) do
      assert_enqueued_jobs 1, only: EmailDeliveryJob do
        post "/api/auth/otp/request", params: { email: "newbie@example.com", name: "New Person", role: "jobseeker" }, as: :json
      end
      assert_no_enqueued_jobs { post "/api/auth/otp/request", params: { email: "ghost@example.com" }, as: :json }
    end
    job = enqueued_jobs.find { _1[:job] == EmailDeliveryJob }
    user_id, template, sealed_code, sealed_email = ActiveJob::Arguments.deserialize(job[:args])
    assert_nil user_id
    assert_equal "sign_in_code", template
    code = EmailDeliveryJob.unseal(sealed_code)
    assert_match(/\A\d{6}\z/, code)
    assert_equal "newbie@example.com", EmailDeliveryJob.unseal(sealed_email, purpose: EmailDeliveryJob::RECIPIENT_PURPOSE)
    assert_not_includes job[:args].to_json, "newbie@example.com"
    assert_not_includes job[:args].to_json, code

    sent = nil
    EmailDelivery.stub(:call, ->(**kwargs) { sent = kwargs; { delivered: true, status: 200 } }) do
      EmailDeliveryJob.perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    assert_equal "newbie@example.com", sent[:to]
    assert_equal({ code: }, sent[:data])

    with_env(PROVIDER_ENV) do
      assert_enqueued_jobs 1, only: EmailDeliveryJob do
        post "/api/auth/otp/request", params: { email: "coder@example.com" }, as: :json
      end
    end
    user_id, _template, _sealed, sealed_email = ActiveJob::Arguments.deserialize(enqueued_jobs.last[:args])
    assert_equal @user.id, user_id
    assert_nil sealed_email
  end

  test "the sign-in code email renders the code without a link" do
    with_env("BREVO_API_KEY" => "k", "BREVO_SENDER_EMAIL" => "sender@example.invalid") do
      body = nil
      transport = lambda do |_url, &configure|
        request = Struct.new(:headers, :body, :options).new({}, nil, Struct.new(:open_timeout, :timeout).new)
        configure.call(request)
        body = JSON.parse(request.body)
        Struct.new(:status) { def success? = true }.new(201)
      end
      Faraday.stub(:post, transport) do
        EmailDelivery.call(to: "a@example.com", template: "sign_in_code", data: { code: "042917" })
      end
      assert_equal "Your MusiLynk sign-in code", body["subject"]
      assert_includes body["textContent"], "042917"
      assert_includes body["htmlContent"], "042917"
      assert_not_includes body["htmlContent"], "href="
    end
  end

  test "unknown email with name and role creates the account only on verify" do
    code = nil
    assert_no_difference -> { User.count } do
      code = request_code("fresh@example.com", name: " Fresh Face ", role: "jobseeker")
    end
    assert_difference -> { User.count }, 1 do
      verify("fresh@example.com", code)
    end
    assert_response :success
    user = User.find_by!(email: "fresh@example.com")
    assert_equal "Fresh Face", user.name
    assert user.jobseeker?
    assert user.email_verified?
    assert user.profile
    assert_equal false, response.parsed_body.dig("user", "profileComplete")
    assert_equal "auth.register", AuditLog.last.action
  end

  test "unknown email without sign-up details never gets a usable code" do
    code = request_code("ghost@example.com")
    verify("ghost@example.com", code)
    assert_response :unauthorized
    assert_nil User.find_by(email: "ghost@example.com")
  end

  test "invalid sign-up details are rejected the same way for known and unknown addresses" do
    %w[coder@example.com nobody@example.com].each do |email|
      post "/api/auth/otp/request", params: { email:, name: "Admin Wannabe", role: "admin" }, as: :json
      assert_response :unprocessable_content
      assert_equal "INVALID_ROLE", response.parsed_body["code"]
      post "/api/auth/otp/request", params: { email:, name: "X", role: "employer" }, as: :json
      assert_response :unprocessable_content
      assert_equal "INVALID_NAME", response.parsed_body["code"]
    end
    post "/api/auth/otp/request", params: { email: "not-an-email" }, as: :json
    assert_response :unprocessable_content
    assert_equal "INVALID_EMAIL", response.parsed_body["code"]
  end

  test "codes expire after ten minutes" do
    code = request_code("coder@example.com")
    travel 10.minutes + 1.second do
      verify("coder@example.com", code)
      assert_response :unauthorized
      assert_equal "Invalid or expired code.", response.parsed_body["error"]
      assert_equal "OTP_INVALID", response.parsed_body["code"]
    end
  end

  test "codes are single use" do
    code = request_code("coder@example.com")
    verify("coder@example.com", code)
    assert_response :success
    verify("coder@example.com", code)
    assert_response :unauthorized
  end

  test "a code is burned after five wrong attempts even if the sixth is right" do
    code = request_code("coder@example.com")
    wrong = code == "000000" ? "111111" : "000000"
    SignInCode::MAX_ATTEMPTS.times do
      verify("coder@example.com", wrong)
      assert_response :unauthorized
    end
    verify("coder@example.com", code)
    assert_response :unauthorized
    assert SignInCode.last.used_at
    assert_equal SignInCode::MAX_ATTEMPTS, SignInCode.last.attempts
  end

  test "malformed codes count as attempts and fail generically" do
    code = request_code("coder@example.com")
    ["", "12345", "abcdef", "1234567", nil].each do |bad|
      verify("coder@example.com", bad)
      assert_response :unauthorized
    end
    verify("coder@example.com", " #{code[0, 3]} #{code[3, 3]} ")
    assert_response :unauthorized, "fifth attempt exhausted the code"
    code = request_code("coder@example.com")
    verify("coder@example.com", " #{code[0, 3]} #{code[3, 3]} ")
    assert_response :success, "spaces from a pasted code are ignored"
  end

  test "a new request invalidates the previous code" do
    first = request_code("coder@example.com")
    second = request_code("coder@example.com")
    verify("coder@example.com", first) unless first == second
    assert_response :unauthorized unless first == second
    verify("coder@example.com", second)
    assert_response :success
  end

  test "requests are throttled per email and per IP with the same response" do
    SignInCode.delete_all
    AuthController::OTP_REQUESTS_PER_EMAIL.times do |index|
      post "/api/auth/otp/request", params: { email: "coder@example.com" }, env: { "REMOTE_ADDR" => "198.51.100.#{index + 1}" }, as: :json
      assert_response :success
    end
    post "/api/auth/otp/request", params: { email: "coder@example.com" }, env: { "REMOTE_ADDR" => "198.51.100.77" }, as: :json
    assert_response :too_many_requests
    post "/api/auth/otp/request", params: { email: "ghost@example.com" }, env: { "REMOTE_ADDR" => "198.51.100.77" }, as: :json
    assert_response :success

    AuthController::OTP_REQUESTS_PER_IP.times do |index|
      post "/api/auth/otp/request", params: { email: "spray#{index}@example.com" }, env: { "REMOTE_ADDR" => "203.0.113.5" }, as: :json
      assert_response :success
    end
    post "/api/auth/otp/request", params: { email: "coder2@example.com" }, env: { "REMOTE_ADDR" => "203.0.113.5" }, as: :json
    assert_response :too_many_requests

    travel AuthController::OTP_REQUEST_PERIOD + 1.second do
      post "/api/auth/otp/request", params: { email: "coder@example.com" }, env: { "REMOTE_ADDR" => "203.0.113.5" }, as: :json
      assert_response :success
    end
  end

  test "verification failures are throttled per IP" do
    AuthController::OTP_VERIFY_FAILURES_PER_IP.times do |index|
      verify("target#{index}@example.com", "123456", ip: "198.51.100.9")
      assert_response :unauthorized
    end
    code = request_code("coder@example.com")
    verify("coder@example.com", code, ip: "198.51.100.9")
    assert_response :too_many_requests
    verify("coder@example.com", code, ip: "198.51.100.10")
    assert_response :success
  end

  test "suspended and pending accounts get 403 with a correct code" do
    %w[suspended pending].each do |status|
      @user.update!(status:)
      code = request_code("coder@example.com")
      verify("coder@example.com", code)
      assert_response :forbidden
      assert_equal "This account is not active.", response.parsed_body["error"]
      assert_equal 0, @user.sessions.count
    end
  end

  test "debugCode is never returned in production" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    with_env(PROVIDER_ENV) do
      Rails.stub(:env, production) { post "/api/auth/otp/request", params: { email: "coder@example.com" }, as: :json }
    end
    assert_response :success
    assert_nil response.parsed_body["debugCode"]
  end

  test "production without an email provider refuses to promise a code, the same way for every address" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    bodies = %w[coder@example.com nobody@example.com].map do |email|
      with_env(NO_PROVIDER_ENV) do
        Rails.stub(:env, production) { post "/api/auth/otp/request", params: { email: }, as: :json }
      end
      assert_response :service_unavailable
      response.parsed_body
    end
    assert_equal "OTP_UNAVAILABLE", bodies.first["code"]
    assert_equal bodies.first, bodies.last, "the response must not reveal whether an account exists"
    assert_nil bodies.first["debugCode"]
    assert_equal 0, SignInCode.count, "no code is issued that could never be delivered"
  end

  test "sign-in methods report whether emailed codes can be delivered" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    providers = { "google" => false, "whatsapp" => false }
    with_env(NO_PROVIDER_ENV) { Rails.stub(:env, production) { get "/api/auth/methods" } }
    assert_response :success
    assert_equal({ "signInCodes" => false, "password" => true, "emailDelivery" => false, "providers" => providers }, response.parsed_body)

    with_env(PROVIDER_ENV) { Rails.stub(:env, production) { get "/api/auth/methods" } }
    assert_equal({ "signInCodes" => true, "password" => true, "emailDelivery" => true, "providers" => providers }, response.parsed_body)

    with_env(NO_PROVIDER_ENV) { get "/api/auth/methods" }
    assert response.parsed_body["signInCodes"], "outside production the on-screen debug code stands in for email"
    assert_equal false, response.parsed_body["emailDelivery"]

    with_env(NO_PROVIDER_ENV.merge("PASSWORD_LOGIN_ENABLED" => "false")) { get "/api/auth/methods" }
    assert_equal false, response.parsed_body["password"]
  end

  test "codes do not appear in logs" do
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    code = request_code("coder@example.com")
    verify("coder@example.com", code)
    assert_response :success
    Rails.logger = original
    assert_not_includes io.string, code
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter("code" => code)["code"]
  ensure
    Rails.logger = original
  end

  test "PASSWORD_LOGIN_ENABLED=false turns off password login but not codes" do
    # A verified address keeps its password when a code is used (an unverified one is reclaimed: see the audit tests).
    User.find_by!(email: "coder@example.com").update_columns(email_verified: true)
    with_env("PASSWORD_LOGIN_ENABLED" => "false") do
      post "/api/auth/login", params: { email: "coder@example.com", password: PASSWORD }, as: :json
      assert_response :forbidden
      assert_equal "PASSWORD_LOGIN_DISABLED", response.parsed_body["code"]
      code = request_code("coder@example.com")
      verify("coder@example.com", code)
      assert_response :success
    end
    with_env("PASSWORD_LOGIN_ENABLED" => nil) do
      post "/api/auth/login", params: { email: "coder@example.com", password: PASSWORD }, as: :json
      assert_response :success
    end
  end

  test "reclaiming an unverified account never fails on the random password containing the user's name" do
    SecureRandom.stub(:base58, "xxCoDeUserxx#{'a' * 20}") { assert_nothing_raised { @user.reclaim_unverified_credentials! } }
    assert_nil @user.reload.password_set_at
  end

  private

  def request_code(email, ip: "127.0.0.1", **extra)
    with_env(NO_PROVIDER_ENV) do
      post "/api/auth/otp/request", params: { email:, **extra }, env: { "REMOTE_ADDR" => ip }, as: :json
    end
    assert_response :success
    response.parsed_body.fetch("debugCode")
  end

  def verify(email, code, ip: "127.0.0.1")
    post "/api/auth/otp/verify", params: { email:, code: }, env: { "REMOTE_ADDR" => ip }, as: :json
  end

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
