require "test_helper"

class BillingReconciliationTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Billing Test", email: "billing-p0-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "employer", status: "active")
    @user.create_profile!
    @token = SecureRandom.urlsafe_base64(48)
    @user.sessions.create!(token_digest: Digest::SHA256.hexdigest(@token), expires_at: 1.day.from_now)
    @previous_env = ENV.to_h.slice("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_PLAN_PRO", "RAZORPAY_WEBHOOK_SECRET")
    ENV["RAZORPAY_KEY_ID"] = "rzp_test_key"
    ENV["RAZORPAY_KEY_SECRET"] = "rzp_test_secret"
    ENV["RAZORPAY_PLAN_PRO"] = "plan_pro"
    ENV["RAZORPAY_WEBHOOK_SECRET"] = "webhook-test-secret"
  end

  teardown do
    %w[RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_PLAN_PRO RAZORPAY_WEBHOOK_SECRET].each { ENV.delete(_1) }
    @previous_env.each { |key, value| ENV[key] = value }
  end

  test "plan catalog matches the live Razorpay monthly prices" do
    get "/api/billing/plans"

    assert_response :success
    plans = response.parsed_body.fetch("plans").index_by { |plan| plan.fetch("code") }
    assert_equal 2499, plans.fetch("pro").fetch("monthly")
    assert_equal 5999, plans.fetch("studio").fetch("monthly")
  end

  test "provider creation remains pending and does not grant paid entitlement" do
    gateway = fake_gateway(create_subscription: { "id" => "sub_pending", "status" => "created" })

    with_gateway(gateway) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "checkout-one"), as: :json
    end

    assert_response :success, response.body
    subscription = Subscription.find(response.parsed_body.dig("subscription", "id"))
    assert_equal "pending", subscription.status
    assert_nil subscription.trial_started_at
    assert_equal "succeeded", BillingAttempt.find_by!(resource_id: subscription.id).state

    get "/api/billing/subscription", headers: auth
    assert_response :success
    assert_equal "free", response.parsed_body.dig("plan", "code")

    payload = { event: "subscription.authenticated", created_at: Time.current.to_i, payload: { subscription: { entity: { id: "sub_pending" } } } }
    raw = JSON.generate(payload)
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_WEBHOOK_SECRET"), raw)
    post "/api/billing/webhook/razorpay", params: raw, headers: { "CONTENT_TYPE" => "application/json", "X-Razorpay-Signature" => signature, "X-Razorpay-Event-Id" => "evt_authenticated" }
    assert_response :success

    get "/api/billing/subscription", headers: auth
    assert_equal "pro", response.parsed_body.dig("plan", "code")
    assert subscription.reload.trial_started_at.present?
  end

  test "ambiguous provider timeout is durable and the same key cannot create again" do
    timeout = RazorpayGateway::GatewayError.new("timed out", code: "timeout", ambiguous: true)
    gateway = fake_gateway(create_subscription: timeout)

    with_gateway(gateway) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "ambiguous-one"), as: :json
      assert_response :bad_gateway
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "ambiguous-one"), as: :json
    end

    assert_response :conflict
    attempt = BillingAttempt.find_by!(idempotency_key: "#{@user.id}:subscription_create:ambiguous-one")
    assert_equal "ambiguous", attempt.state
    assert_equal "timeout", attempt.error_code
    assert_equal "pending", Subscription.find(attempt.resource_id).status
  end

  test "reconciler attaches a known provider subscription and closes the attempt" do
    subscription = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    attempt = BillingAttempt.create!(user: @user, operation: "subscription_create", provider: "razorpay", idempotency_key: "reconcile-one", state: "ambiguous", resource_type: "Subscription", resource_id: subscription.id, provider_resource_id: "sub_recovered")
    gateway = fake_gateway(subscription: { "id" => "sub_recovered", "status" => "created" })

    BillingAttemptReconciler.new(gateway:).call(attempt)

    assert_equal "sub_recovered", subscription.reload.provider_subscription_id
    assert_equal "succeeded", attempt.reload.state
  end

  private

  def auth = { "Authorization" => "Bearer #{@token}" }

  def with_gateway(gateway)
    original = RazorpayGateway.method(:new)
    RazorpayGateway.define_singleton_method(:new) { gateway }
    yield
  ensure
    RazorpayGateway.define_singleton_method(:new, original)
  end

  def fake_gateway(responses)
    Object.new.tap do |gateway|
      responses.each do |method, value|
        gateway.define_singleton_method(method) do |*_args, **_kwargs|
          raise value if value.is_a?(Exception)
          value
        end
      end
      gateway.define_singleton_method(:cancel_subscription) { |_id| {} }
    end
  end
end
