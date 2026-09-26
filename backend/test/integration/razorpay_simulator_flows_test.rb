require "test_helper"
require "minitest/mock"

# Complete billing and booking-deposit flows against the local Razorpay simulator: the real
# RazorpayGateway (Faraday, Basic auth, error mapping) talks to RazorpaySimulator::Adapter,
# checkout is played by the dev simulator endpoint and webhooks are delivered signed.
class RazorpaySimulatorFlowsTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "simulator-webhook-secret"
  ENV_KEYS = %w[RAZORPAY_SIMULATOR RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_WEBHOOK_SECRET RAZORPAY_PLAN_PRO RAZORPAY_PLAN_STUDIO RAZORPAY_ALLOW_LIVE_MODE RAZORPAY_ALLOW_TEST_MODE].freeze

  setup do
    @previous_env = ENV_KEYS.to_h { [_1, ENV[_1]] }
    ENV.update("RAZORPAY_SIMULATOR" => "true", "RAZORPAY_KEY_ID" => "rzp_test_simulator", "RAZORPAY_KEY_SECRET" => "sim_secret_#{SecureRandom.hex(4)}",
               "RAZORPAY_WEBHOOK_SECRET" => WEBHOOK_SECRET, "RAZORPAY_PLAN_PRO" => "plan_SimPro", "RAZORPAY_PLAN_STUDIO" => "plan_SimStudio")
    ENV.delete("RAZORPAY_ALLOW_LIVE_MODE")
    ENV.delete("RAZORPAY_ALLOW_TEST_MODE")
    RazorpaySimulator.reset!
    @user, @token = create_user("Sim Buyer", "employer")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    RazorpaySimulator.reset!
  end

  # ---- Subscriptions ----------------------------------------------------------------------

  test "trial subscribe, authenticate, activate, charge, halt, resume, cancel at cycle end, complete" do
    sub_id = start_checkout("pro")
    local = Subscription.find_by!(provider_subscription_id: sub_id)
    assert_equal "pending", local.status
    remote = simulator.subscription(sub_id)
    assert_equal "plan_SimPro", remote["plan_id"]
    assert_operator remote["start_at"], :>, Time.current.to_i + 13.days.to_i, "the 14-day trial is expressed as a deferred start"
    assert_equal local.user_id.to_s, remote.dig("notes", "user_id")

    handler = simulate_checkout(subscriptionId: sub_id, outcome: "success")
    response_payload = handler.fetch("response")
    assert_equal sub_id, response_payload["razorpay_subscription_id"]
    assert_equal hmac("#{response_payload["razorpay_payment_id"]}|#{sub_id}"), response_payload["razorpay_signature"]
    assert_equal "pending", local.reload.status, "the browser handler alone never grants access"

    deliver_all(handler.fetch("webhooks"))
    assert_equal "trialing", local.reload.status
    assert_equal "pro", Entitlements.for(@user).plan_code
    summary = billing_state.fetch("summary")
    assert_equal "trialing", summary["status"]
    assert_equal local.trial_ends_at.to_i, Time.zone.parse(summary["nextChargeAt"]).to_i

    travel 15.days do
      lifecycle(sub_id, "activate")
      local.reload
      assert_equal "active", local.status
      remote = simulator.subscription(sub_id)
      assert_equal Time.at(remote["current_start"]).utc.to_i, local.current_period_start.to_i
      assert_equal Time.at(remote["current_end"]).utc.to_i, local.current_period_end.to_i
      state = billing_state
      assert_equal "active", state.dig("summary", "status")
      assert_equal local.current_period_end.to_i, Time.zone.parse(state.dig("summary", "nextChargeAt")).to_i
      assert_equal [2499.0], state.fetch("history").map { _1["amount"] }
    end

    travel 46.days do
      first_end = local.current_period_end
      lifecycle(sub_id, "charge")
      assert_operator local.reload.current_period_end, :>, first_end
      assert_equal 2, billing_state.fetch("history").size
    end

    travel 50.days do
      lifecycle(sub_id, "halt")
      assert_equal "past_due", local.reload.status
      assert_equal "free", Entitlements.for(@user).plan_code, "past_due grants no paid capacity"
      assert_equal "past_due", billing_state.dig("summary", "status")

    end

    travel 51.days do
      lifecycle(sub_id, "resume")
      assert_equal "active", local.reload.status
      assert_equal "pro", Entitlements.for(@user).plan_code

      post "/api/billing/cancel", headers: auth, as: :json
      assert_response :success
      assert_equal "scheduled", response.parsed_body["outcome"]
      assert simulator.subscription(sub_id)["has_scheduled_changes"], "Razorpay was asked to cancel at cycle end"
      assert_equal "active", simulator.subscription(sub_id)["status"]
      state = billing_state
      assert_equal "cancelling", state.dig("summary", "status")
      assert_nil state.dig("summary", "nextChargeAt")
      assert_equal local.reload.current_period_end.to_i, Time.zone.parse(state.dig("summary", "accessEndsAt")).to_i

      post "/api/billing/cancel", headers: auth, as: :json
      assert_response :conflict
    end

    travel 77.days do
      lifecycle(sub_id, "complete")
      assert_equal "cancelled", local.reload.status
      state = billing_state
      assert_nil state["subscription"]
      assert_equal "cancelled", state.dig("summary", "status"), "the ended plan is still explained"
      assert_equal "free", state.dig("plan", "code")
    end
  end

  test "a failed renewal (subscription.pending) moves the plan to past_due, a later charge recovers it" do
    sub_id = active_subscription("pro")
    travel 31.days
    lifecycle(sub_id, "pending")
    assert_equal "past_due", Subscription.find_by!(provider_subscription_id: sub_id).status
    assert_equal "failed", billing_state.fetch("history").first["status"]

    travel 2.days
    lifecycle(sub_id, "charge")
    assert_equal "active", Subscription.find_by!(provider_subscription_id: sub_id).status
  end

  test "paused then resumed" do
    sub_id = active_subscription("pro")
    travel 1.day
    lifecycle(sub_id, "pause")
    assert_equal "past_due", Subscription.find_by!(provider_subscription_id: sub_id).status
    travel 1.day
    lifecycle(sub_id, "resume")
    assert_equal "active", Subscription.find_by!(provider_subscription_id: sub_id).status
  end

  test "duplicate and out-of-order webhooks are harmless" do
    sub_id = start_checkout("pro")
    authenticated = simulate_checkout(subscriptionId: sub_id, outcome: "success").fetch("webhooks").first
    travel 15.days do
      events = lifecycle(sub_id, "activate", deliver: false)
      events.each { deliver(_1) }
      local = Subscription.find_by!(provider_subscription_id: sub_id)
      assert_equal "active", local.status

      deliver(authenticated) # older event arrives late
      assert_equal "active", local.reload.status
      assert_equal "stale", BillingEvent.find_by!(provider_event_id: authenticated.dig("headers", "X-Razorpay-Event-Id")).processing_result

      assert_no_difference -> { BillingEvent.count } do
        deliver(events.first)
      end
      assert response.parsed_body["duplicate"]

      tampered = events.last.merge(headers: events.last[:headers].merge("X-Razorpay-Signature" => "0" * 64, "X-Razorpay-Event-Id" => "evt_tampered"))
      deliver(tampered, expect: :unauthorized)
    end
  end

  test "failed and dismissed checkout leave the mandate pending and resumable" do
    sub_id = start_checkout("pro")
    failed = simulate_checkout(subscriptionId: sub_id, outcome: "fail")
    assert_equal "payment_declined", failed.dig("error", "reason")
    assert failed.dig("error", "metadata", "payment_id").start_with?("pay_")
    deliver_all(failed.fetch("webhooks"))
    assert_equal "payment.failed", BillingEvent.order(:created_at).last.event_type

    dismissed = simulate_checkout(subscriptionId: sub_id, outcome: "dismiss")
    assert dismissed["dismissed"]
    assert_equal "pending", Subscription.find_by!(provider_subscription_id: sub_id).status
    assert_equal "free", Entitlements.for(@user).plan_code

    assert_equal sub_id, start_checkout("pro", key: "another-intent"), "Complete setup reuses the same Razorpay subscription"
    assert_equal 1, simulator_subscriptions.size
  end

  test "double click creates one Razorpay subscription and a plan change is refused" do
    first = start_checkout("pro", key: "click")
    second = start_checkout("pro", key: "click")
    assert_equal first, second
    assert_equal 1, simulator_subscriptions.size

    deliver_all(simulate_checkout(subscriptionId: first, outcome: "success").fetch("webhooks"))
    post "/api/billing/checkout", params: { planCode: "studio" }, headers: auth.merge("Idempotency-Key" => "change"), as: :json
    assert_response :conflict
    assert_equal "PLAN_CHANGE_REQUIRES_CANCELLATION", response.parsed_body["code"]
    assert_equal 1, simulator_subscriptions.size
  end

  test "cancelling during the trial cancels immediately at Razorpay" do
    sub_id = start_checkout("pro")
    deliver_all(simulate_checkout(subscriptionId: sub_id, outcome: "success").fetch("webhooks"))
    post "/api/billing/cancel", headers: auth, as: :json
    assert_response :success
    assert_equal "cancelled", response.parsed_body["outcome"]
    assert_equal "cancelled", simulator.subscription(sub_id)["status"]
    assert_equal "cancelled", Subscription.find_by!(provider_subscription_id: sub_id).status

    # Razorpay's own cancellation webhook arriving afterwards changes nothing.
    events = RazorpaySimulator.instance.send(:event, "subscription.cancelled", subscription: simulator.subscription(sub_id))
    deliver(RazorpaySimulator::Webhooks.signed(events))
    assert_equal "cancelled", Subscription.find_by!(provider_subscription_id: sub_id).status
  end

  test "a confirmed trial cancellation applies even when Razorpay's clock is ahead of ours" do
    sub_id = start_checkout("pro")
    deliver_all(simulate_checkout(subscriptionId: sub_id, outcome: "success").fetch("webhooks"))
    local = Subscription.find_by!(provider_subscription_id: sub_id)
    local.update_columns(provider_state_at: 5.seconds.from_now)

    post "/api/billing/cancel", headers: auth, as: :json
    assert_response :success
    assert_equal "cancelled", local.reload.status
    get "/api/billing/subscription", headers: auth
    assert_equal "cancelled", response.parsed_body.dig("summary", "status")
  end

  test "plan, amount and currency never come from the client" do
    post "/api/billing/checkout", params: { planCode: "pro", planId: "plan_SimStudio", amount: 1, currency: "USD", trialDays: 365 }, headers: auth.merge("Idempotency-Key" => "tamper"), as: :json
    assert_response :success
    remote = simulator.subscription(response.parsed_body.dig("checkout", "subscriptionId"))
    assert_equal "plan_SimPro", remote["plan_id"]
    assert_operator remote["start_at"], :<, 15.days.from_now.to_i

    _requester, booking = accepted_booking(requester: @user)
    post "/api/bookings/#{booking.id}/payment-order", params: { amount: 1, currency: "USD", depositPercent: 1 }, headers: auth, as: :json
    assert_response :success
    order = simulator.order(response.parsed_body.dig("checkout", "orderId"))
    assert_equal 500_000, order["amount"]
    assert_equal "INR", order["currency"]
  end

  test "the subscription endpoint exposes only a testMode boolean, never keys" do
    get "/api/billing/subscription", headers: auth
    assert_response :success
    assert_equal true, response.parsed_body["testMode"]
    assert_not_includes response.body, ENV["RAZORPAY_KEY_SECRET"]
    assert_not_includes response.body, WEBHOOK_SECRET
  end

  # ---- Booking deposits -------------------------------------------------------------------

  test "deposit order, successful payment (webhook first), confirm, refund" do
    _requester, booking = accepted_booking(requester: @user)
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    assert_response :success
    checkout = response.parsed_body.fetch("checkout")
    assert checkout["simulator"]
    assert_equal 500_000, checkout["amount"]
    payment = BookingPayment.find(response.parsed_body.dig("payment", "id"))

    result = simulate_checkout(orderId: checkout["orderId"], outcome: "success")
    handler = result.fetch("response")
    assert_equal hmac("#{checkout["orderId"]}|#{handler["razorpay_payment_id"]}"), handler["razorpay_signature"]
    deliver_all(result.fetch("webhooks"))
    assert_equal "paid", payment.reload.status

    confirm(payment, handler)
    assert_response :success, response.body
    assert response.parsed_body["alreadyConfirmed"], "a webhook that won the race is not an error"

    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    assert_response :conflict
    assert_equal "Deposit is already paid.", response.parsed_body["error"]

    post "/api/dev/razorpay/payments/#{handler["razorpay_payment_id"]}/refund", headers: auth, as: :json
    assert_response :success
    deliver_all(response.parsed_body.fetch("webhooks"))
    assert_equal "refunded", payment.reload.status
    get "/api/bookings/#{booking.id}/payments", headers: auth
    assert_equal ["refunded"], response.parsed_body["payments"].map { _1["status"] }
  end

  test "handler first: confirm verifies with Razorpay, the late webhook is a no-op" do
    _requester, booking = accepted_booking(requester: @user)
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    payment = BookingPayment.find(response.parsed_body.dig("payment", "id"))
    result = simulate_checkout(orderId: payment.provider_order_id, outcome: "success")

    handler = result.fetch("response")
    confirm(payment, handler.merge("razorpay_signature" => "f" * 64))
    assert_response :unprocessable_content
    confirm(payment, handler)
    assert_response :success
    assert_equal "paid", payment.reload.status
    deliver_all(result.fetch("webhooks"))
    assert_includes %w[already_paid stale], BillingEvent.find_by!(event_type: "payment.captured").processing_result
    assert_equal "paid", payment.reload.status
  end

  test "a declined payment can be retried in the same checkout or with a new order" do
    _requester, booking = accepted_booking(requester: @user)
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    first = BookingPayment.find(response.parsed_body.dig("payment", "id"))

    declined = simulate_checkout(orderId: first.provider_order_id, outcome: "fail")
    assert_equal first.provider_order_id, declined.dig("error", "metadata", "order_id")
    deliver_all(declined.fetch("webhooks"))
    assert_equal "failed", first.reload.status

    # Retry inside the same Razorpay checkout (same order) succeeds.
    retried = simulate_checkout(orderId: first.provider_order_id, outcome: "success")
    confirm(first, retried.fetch("response"))
    assert_response :success, response.body
    assert_equal "paid", first.reload.status

    # A second booking: decline, close the modal, and pay again with a fresh order.
    _requester, other = accepted_booking(requester: @user)
    post "/api/bookings/#{other.id}/payment-order", headers: auth, as: :json
    order_a = response.parsed_body.dig("checkout", "orderId")
    deliver_all(simulate_checkout(orderId: order_a, outcome: "fail").fetch("webhooks"))
    post "/api/bookings/#{other.id}/payment-order", headers: auth, as: :json
    assert_response :success
    order_b = response.parsed_body.dig("checkout", "orderId")
    assert_not_equal order_a, order_b
    retry_payment = BookingPayment.find(response.parsed_body.dig("payment", "id"))
    result = simulate_checkout(orderId: order_b, outcome: "success")
    confirm(retry_payment, result.fetch("response"))
    assert_response :success
    assert_equal %w[failed paid], other.booking_payments.order(:created_at).pluck(:status)
  end

  # ---- Reconciliation ---------------------------------------------------------------------

  test "a subscription whose create response was lost is recovered by the reconciliation job" do
    simulator.inject_fault(:create_subscription, :timeout_after)
    post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "lost"), as: :json
    assert_response :bad_gateway
    attempt = BillingAttempt.find_by!(user: @user, operation: "subscription_create")
    assert_equal "ambiguous", attempt.state
    assert_nil attempt.provider_resource_id
    assert_equal 1, simulator_subscriptions.size, "Razorpay did create it"

    post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "lost"), as: :json
    assert_response :conflict

    result = BillingReconciliationJob.perform_now(3.minutes.from_now)
    assert_equal 1, result[:reconciled]
    assert_equal "succeeded", attempt.reload.state
    remote_id = simulator_subscriptions.first["id"]
    assert_equal remote_id, Subscription.find(attempt.resource_id).provider_subscription_id

    post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "lost"), as: :json
    assert_response :success
    assert_equal remote_id, response.parsed_body.dig("checkout", "subscriptionId")
  end

  test "an order whose create failed with a 5xx is recovered, and a missing one goes stale" do
    _requester, booking = accepted_booking(requester: @user)
    simulator.inject_fault(:create_order, :server_error)
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    assert_response :bad_gateway
    payment = booking.booking_payments.sole
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    assert_response :conflict

    BillingReconciliationJob.perform_now(3.minutes.from_now)
    assert payment.reload.provider_order_id.start_with?("order_")
    post "/api/bookings/#{booking.id}/payment-order", headers: auth, as: :json
    assert_response :success
    assert_equal payment.provider_order_id, response.parsed_body.dig("checkout", "orderId")

    _requester, lost = accepted_booking(requester: @user)
    simulator.inject_fault(:create_order, :timeout_before)
    post "/api/bookings/#{lost.id}/payment-order", headers: auth, as: :json
    assert_response :bad_gateway
    BillingReconciliationJob.perform_now(3.minutes.from_now)
    assert_equal "ambiguous", BillingAttempt.find_by!(resource_id: lost.booking_payments.sole.id).state, "young and absent: left alone"
    BillingReconciliationJob.perform_now(31.minutes.from_now)
    assert_equal "failed", lost.booking_payments.sole.status
  end

  # ---- Gateway fidelity and guards ----------------------------------------------------------

  test "wrong credentials are rejected like Razorpay does, without ambiguity" do
    gateway = RazorpayGateway.new
    ENV["RAZORPAY_KEY_SECRET"] = "wrong"
    error = assert_raises(RazorpayGateway::GatewayError) { gateway.create_order(amount_paise: 1000, currency: "INR", receipt: "r") }
    assert_equal 401, error.http_status
    assert_equal "Authentication failed", error.message
    assert_not error.ambiguous?
  end

  test "invalid requests surface Razorpay's error envelope" do
    error = assert_raises(RazorpayGateway::GatewayError) { RazorpayGateway.new.create_order(amount_paise: 50, currency: "INR", receipt: "r") }
    assert_equal "BAD_REQUEST_ERROR", error.code
    assert_match(/atleast/, error.message)
    error = assert_raises(RazorpayGateway::GatewayError) { RazorpayGateway.new.payment("pay_missing") }
    assert_equal "The id provided does not exist", error.message
  end

  test "the simulator and its routes are unavailable when disabled, with live keys, or in production" do
    post "/api/dev/razorpay/checkout", params: { subscriptionId: "sub_x", outcome: "success" }, headers: auth, as: :json
    assert_response :not_found # unknown subscription for this user

    ENV["RAZORPAY_KEY_ID"] = "rzp_live_nope"
    ENV["RAZORPAY_ALLOW_LIVE_MODE"] = "true"
    assert_not RazorpayConfig.simulator?
    post "/api/dev/razorpay/checkout", params: { subscriptionId: "sub_x", outcome: "success" }, headers: auth, as: :json
    assert_response :not_found
    assert_raises(RazorpaySimulator::Refused) { RazorpaySimulator.instance.handle(:get, "https://api.razorpay.com/v1/orders", nil, nil) }

    ENV["RAZORPAY_KEY_ID"] = "rzp_test_simulator"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_not RazorpayConfig.simulator?
      assert_not RazorpaySimulator.enabled?
      %w[/api/dev/razorpay/checkout /api/dev/razorpay/webhooks /api/dev/razorpay/subscriptions/sub_x/activate /api/dev/razorpay/payments/pay_x/refund].each do |path|
        post path, params: { outcome: "success" }, headers: auth, as: :json
        assert_response :not_found, path
      end
      ENV["RAZORPAY_ALLOW_TEST_MODE"] = "true"
      adapter = RazorpayGateway.new.send(:connection).builder.adapter
      assert_equal Faraday::Adapter::NetHttp, adapter.klass
    end

    ENV["RAZORPAY_SIMULATOR"] = "false"
    post "/api/dev/razorpay/webhooks", params: { payload: { event: "x" } }, headers: auth, as: :json
    assert_response :not_found
  end

  test "the dev checkout endpoint only acts on the caller's own resources" do
    sub_id = start_checkout("pro")
    _other, other_token = create_user("Someone Else", "employer")
    post "/api/dev/razorpay/checkout", params: { subscriptionId: sub_id, outcome: "success" }, headers: { "Authorization" => "Bearer #{other_token}" }, as: :json
    assert_response :not_found
    assert_equal "created", simulator.subscription(sub_id)["status"]
  end

  test "admin reconcile fails closed with 503 when Razorpay is not configured" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    attempt = BillingAttempt.create!(user: @user, operation: "subscription_create", provider: "razorpay", idempotency_key: "unconfigured-#{SecureRandom.hex(4)}", state: "ambiguous", resource_type: "Subscription", resource_id: sub.id)
    _admin, admin_token = create_user("Recon Admin", "admin")
    %w[RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_SIMULATOR].each { ENV.delete(_1) }

    post "/api/admin/billing-attempts/#{attempt.id}/reconcile", headers: { "Authorization" => "Bearer #{admin_token}" }, as: :json

    assert_response :service_unavailable
    assert_equal "PAYMENTS_NOT_CONFIGURED", response.parsed_body["code"]
    assert_equal "ambiguous", attempt.reload.state
    error = assert_raises(RazorpayGateway::GatewayError) { RazorpayGateway.new }
    assert_equal "not_configured", error.code
  end

  test "booking payment history is bounded" do
    _requester, booking = accepted_booking(requester: @user)
    quote = booking.booking_quotes.first
    (BookingsController::PAYMENTS_LIMIT + 3).times { booking.booking_payments.create!(booking_quote: quote, payer: @user, kind: "deposit", amount: 10, currency: "INR", provider: "internal", status: "failed") }
    get "/api/bookings/#{booking.id}/payments", headers: auth
    assert_response :success
    assert_equal BookingsController::PAYMENTS_LIMIT, response.parsed_body["payments"].size
  end

  test "admins can read billing events; other users cannot" do
    sub_id = start_checkout("pro")
    deliver_all(simulate_checkout(subscriptionId: sub_id, outcome: "success").fetch("webhooks"))
    admin, admin_token = create_user("Billing Admin", "admin")
    get "/api/admin/billing-events", headers: { "Authorization" => "Bearer #{admin_token}" }
    assert_response :success
    event = response.parsed_body["events"].first
    assert_equal "subscription.authenticated", event["eventType"]
    assert_equal sub_id, event["subscriptionId"]
    assert_nil event["payload"]
    get "/api/admin/billing-events/#{event["id"]}", headers: { "Authorization" => "Bearer #{admin_token}" }
    assert_equal "subscription.authenticated", response.parsed_body.dig("event", "payload", "event")
    get "/api/admin/billing-events", params: { eventType: "payment.captured" }, headers: { "Authorization" => "Bearer #{admin_token}" }
    assert_empty response.parsed_body["events"]
    assert admin.admin?

    get "/api/admin/billing-events", headers: auth
    assert_response :forbidden
  end

  private

  def simulator = RazorpaySimulator.instance

  def simulator_subscriptions = RazorpayGateway.new.subscriptions(from: 1.hour.ago)["items"]

  def start_checkout(plan, key: SecureRandom.uuid)
    post "/api/billing/checkout", params: { planCode: plan }, headers: auth.merge("Idempotency-Key" => key), as: :json
    assert_response :success, response.body
    checkout = response.parsed_body.fetch("checkout")
    assert_equal "razorpay", checkout["mode"]
    assert_equal true, checkout["simulator"]
    checkout.fetch("subscriptionId")
  end

  def active_subscription(plan)
    sub_id = start_checkout(plan)
    deliver_all(simulate_checkout(subscriptionId: sub_id, outcome: "success").fetch("webhooks"))
    lifecycle(sub_id, "activate")
    sub_id
  end

  def simulate_checkout(**params)
    post "/api/dev/razorpay/checkout", params:, headers: auth, as: :json
    assert_response :success, response.body
    response.parsed_body
  end

  # Returns the signed webhooks; delivers them unless deliver: false.
  def lifecycle(sub_id, action, deliver: true)
    post "/api/dev/razorpay/subscriptions/#{sub_id}/#{action}", headers: auth, as: :json
    assert_response :success, response.body
    webhooks = response.parsed_body.fetch("webhooks").map { _1.deep_symbolize_keys.then { |w| { body: w[:body], headers: w[:headers].stringify_keys } } }
    deliver_all(webhooks) if deliver
    webhooks
  end

  def deliver_all(webhooks) = webhooks.each { deliver(_1) }

  def deliver(webhook, expect: :success)
    webhook = webhook.deep_symbolize_keys.then { |w| { body: w[:body], headers: w[:headers].stringify_keys } } if webhook.key?("body")
    post "/api/billing/webhook/razorpay", params: webhook[:body], headers: webhook[:headers]
    assert_response expect, response.body
  end

  def confirm(payment, handler)
    post "/api/booking-payments/#{payment.id}/confirm", params: { orderId: handler["razorpay_order_id"], paymentId: handler["razorpay_payment_id"], signature: handler["razorpay_signature"] }, headers: auth, as: :json
  end

  def billing_state
    get "/api/billing/subscription", headers: auth
    assert_response :success
    response.parsed_body
  end

  def hmac(data) = OpenSSL::HMAC.hexdigest("SHA256", ENV["RAZORPAY_KEY_SECRET"], data)

  def auth = { "Authorization" => "Bearer #{@token}" }

  def create_user(name, role)
    user = User.create!(name:, email: "#{role}-#{SecureRandom.hex(5)}@example.com", password: "StrongPass123!", role:, status: "active")
    user.create_profile!
    token = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(token), expires_at: 1.year.from_now)
    [user, token]
  end

  def accepted_booking(requester:)
    owner, = create_user("Act Owner", "jobseeker")
    act = Act.create!(owner:, name: "Simulator Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
    booking = BookingRequest.create!(act:, requester:, event_type: "concert", city: "Mumbai", currency: "INR", status: "accepted")
    booking.booking_quotes.create!(created_by: owner, performance_fee: 10_000, travel_fee: 0, production_fee: 0, other_fee: 0, currency: "INR", deposit_percent: 50, status: "sent")
    [requester, booking]
  end
end
