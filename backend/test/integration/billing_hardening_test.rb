require "test_helper"

class BillingHardeningTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "billing-hardening-webhook-secret"
  RAZORPAY_ENV = %w[RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_PLAN_PRO RAZORPAY_PLAN_STUDIO RAZORPAY_WEBHOOK_SECRET RAZORPAY_ALLOW_LIVE_MODE RAZORPAY_ALLOW_TEST_MODE].freeze

  setup do
    @previous_env = RAZORPAY_ENV.to_h { [_1, ENV[_1]] }
    ENV["RAZORPAY_KEY_ID"] = "rzp_test_hardening"
    ENV["RAZORPAY_KEY_SECRET"] = "rzp_test_hardening_secret"
    ENV["RAZORPAY_PLAN_PRO"] = "plan_pro"
    ENV["RAZORPAY_PLAN_STUDIO"] = "plan_studio"
    ENV["RAZORPAY_WEBHOOK_SECRET"] = WEBHOOK_SECRET
    ENV.delete("RAZORPAY_ALLOW_LIVE_MODE")
    ENV.delete("RAZORPAY_ALLOW_TEST_MODE")
    @user, @token = create_user("Billing Hardening", "employer")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # 1. Live/test key guard

  test "a live key outside production fails closed like missing configuration" do
    ENV["RAZORPAY_KEY_ID"] = "rzp_live_should_not_be_here"
    gateway = recording_gateway

    with_gateway(gateway) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth, as: :json
    end

    assert_response :service_unavailable
    assert_equal "Live billing is not configured.", response.parsed_body.fetch("error")
    assert_empty gateway.calls
    assert_not Subscription.exists?(user: @user)
    assert_raises(RazorpayGateway::GatewayError) { RazorpayGateway.new }
  end

  test "a live key outside production is usable only with the explicit override" do
    ENV["RAZORPAY_KEY_ID"] = "rzp_live_override"
    ENV["RAZORPAY_ALLOW_LIVE_MODE"] = "true"

    with_gateway(recording_gateway(create_subscription: { "id" => "sub_live_override" })) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth, as: :json
    end

    assert_response :success, response.body
    assert_equal "sub_live_override", response.parsed_body.dig("checkout", "subscriptionId")
  end

  test "booking deposits refuse a disallowed key mode" do
    ENV["RAZORPAY_KEY_ID"] = "rzp_live_should_not_be_here"
    _requester, booking = accepted_booking(requester: @user)

    post "/api/bookings/#{booking.id}/payment-order", params: {}, headers: auth, as: :json

    assert_response :service_unavailable
    assert_equal 0, booking.booking_payments.count
  end

  test "public readiness does not expose payment mode" do
    get "/api/readiness"

    body = response.body.downcase
    assert_not_includes body, "rzp_"
    assert_not_includes body, "mode"
    assert_nil response.parsed_body["checks"]
  end

  # 2. Double submit

  test "a second checkout for the same plan while the first is in flight is rejected" do
    in_flight_attempt(plan_code: "pro")
    gateway = recording_gateway(create_subscription: { "id" => "sub_second" })

    with_gateway(gateway) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "second-tab"), as: :json
    end

    assert_response :conflict
    assert_equal "CHECKOUT_IN_PROGRESS", response.parsed_body.fetch("code")
    assert_empty gateway.calls
    assert_equal 1, Subscription.where(user: @user).count
  end

  test "an abandoned in-flight attempt older than two minutes no longer blocks checkout" do
    in_flight_attempt(plan_code: "pro", created_at: 3.minutes.ago)

    with_gateway(recording_gateway(create_subscription: { "id" => "sub_after_abandoned" })) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "later"), as: :json
    end

    assert_response :success, response.body
  end

  test "the same idempotency key replays the created checkout instead of creating another" do
    gateway = recording_gateway(create_subscription: { "id" => "sub_replayed" })

    with_gateway(gateway) do
      2.times { post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth.merge("Idempotency-Key" => "intent-1"), as: :json }
    end

    assert_response :success
    assert_equal "sub_replayed", response.parsed_body.dig("checkout", "subscriptionId")
    assert_equal 1, gateway.calls.count { _1.first == :create_subscription }
  end

  # 3. Plan change

  test "a different paid plan is blocked while a razorpay subscription is live and nothing is cancelled" do
    %w[active trialing pending].each do |status|
      Subscription.where(user: @user).delete_all
      current = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status:, provider_subscription_id: "sub_current_#{status}")
      gateway = recording_gateway(create_subscription: { "id" => "sub_studio" })

      with_gateway(gateway) do
        post "/api/billing/checkout", params: { planCode: "studio" }, headers: auth.merge("Idempotency-Key" => "change-#{status}"), as: :json
      end

      assert_response :conflict
      assert_equal "PLAN_CHANGE_REQUIRES_CANCELLATION", response.parsed_body.fetch("code")
      assert_match(/Cancel your current plan first/, response.parsed_body.fetch("error"))
      assert_empty gateway.calls
      assert_equal status, current.reload.status
      assert_equal 1, Subscription.where(user: @user).count
    end
  end

  test "same plan while active is rejected rather than creating a second mandate" do
    Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "active", provider_subscription_id: "sub_active_pro")
    gateway = recording_gateway(create_subscription: { "id" => "sub_duplicate" })

    with_gateway(gateway) do
      post "/api/billing/checkout", params: { planCode: "pro" }, headers: auth, as: :json
    end

    assert_response :conflict
    assert_equal "ALREADY_SUBSCRIBED", response.parsed_body.fetch("code")
    assert_empty gateway.calls
  end

  test "an admin-granted plan stays active until the paid replacement is authorised" do
    granted = Subscription.create!(user: @user, plan_code: "pro", provider: "internal", status: "active", current_period_start: Time.current, current_period_end: 20.days.from_now)

    with_gateway(recording_gateway(create_subscription: { "id" => "sub_upgrade" })) do
      post "/api/billing/checkout", params: { planCode: "studio" }, headers: auth.merge("Idempotency-Key" => "upgrade"), as: :json
    end
    assert_response :success, response.body
    assert_equal "active", granted.reload.status
    assert_equal "pro", Entitlements.for(@user).plan_code

    post_webhook(subscription_event("subscription.activated", "sub_upgrade", 100), "evt_upgrade_active")
    assert_equal "cancelled", granted.reload.status
    assert_equal "studio", Entitlements.for(@user).plan_code
  end

  test "cancelling an unauthorised pending mandate cancels it immediately so the plan can change" do
    pending = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending", provider_subscription_id: "sub_never_authorised")
    gateway = recording_gateway

    with_gateway(gateway) { post "/api/billing/cancel", params: {}, headers: auth, as: :json }

    assert_response :success, response.body
    assert_equal [[:cancel_subscription, "sub_never_authorised", { at_cycle_end: false }]], gateway.calls
    assert_equal "cancelled", pending.reload.status
  end

  test "cancelling an authorised plan schedules cycle-end cancellation and keeps access" do
    active = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "active", provider_subscription_id: "sub_to_cancel")
    gateway = recording_gateway

    with_gateway(gateway) { post "/api/billing/cancel", params: {}, headers: auth, as: :json }

    assert_response :success
    assert_equal [[:cancel_subscription, "sub_to_cancel", { at_cycle_end: true }]], gateway.calls
    assert_equal "active", active.reload.status
    assert active.cancel_at_period_end
  end

  # 4. Webhooks

  test "completed, paused and resumed subscription events map to allowed statuses" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "active", provider_subscription_id: "sub_lifecycle")

    post_webhook(subscription_event("subscription.paused", "sub_lifecycle", 100), "evt_paused")
    assert_equal "past_due", sub.reload.status
    assert_equal "free", Entitlements.for(@user).plan_code

    post_webhook(subscription_event("subscription.resumed", "sub_lifecycle", 200), "evt_resumed")
    assert_equal "active", sub.reload.status

    post_webhook(subscription_event("subscription.completed", "sub_lifecycle", 300), "evt_completed")
    assert_equal "cancelled", sub.reload.status

    post_webhook(subscription_event("subscription.resumed", "sub_lifecycle", 400), "evt_resumed_after_end")
    assert_equal "cancelled", sub.reload.status
    assert_equal "invalid_transition", BillingEvent.find_by!(provider_event_id: "evt_resumed_after_end").processing_result
  end

  test "a charge moves the billing period forward and a late charge cannot move it back" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "active", provider_subscription_id: "sub_periods")
    first_start = Time.utc(2026, 9, 1)
    second_start = Time.utc(2026, 10, 1)

    post_webhook(subscription_event("subscription.charged", "sub_periods", 100, current_start: second_start.to_i, current_end: (second_start + 1.month).to_i), "evt_charge_2")
    assert_equal second_start, sub.reload.current_period_start
    assert_equal second_start + 1.month, sub.current_period_end

    post_webhook(subscription_event("subscription.charged", "sub_periods", 50, current_start: first_start.to_i, current_end: (first_start + 1.month).to_i), "evt_charge_1_late")
    assert_equal second_start, sub.reload.current_period_start
    assert_equal "stale", BillingEvent.find_by!(provider_event_id: "evt_charge_1_late").processing_result
  end

  test "a failed booking payment frees the deposit for retry and a late capture on that order is still honoured" do
    requester, booking = accepted_booking
    payment = razorpay_payment(booking, requester)

    post_webhook(payment_event("payment.failed", payment, 100, id: "pay_declined", status: "failed"), "evt_payment_failed")
    assert_equal "failed", payment.reload.status
    assert_equal "applied", BillingEvent.find_by!(provider_event_id: "evt_payment_failed").processing_result

    retry_payment = razorpay_payment(booking, requester)
    assert_equal "created", retry_payment.status

    # The customer retried inside the original checkout and it succeeded.
    post_webhook(payment_event("payment.captured", payment, 200, id: "pay_second_try"), "evt_late_capture")
    assert_equal "paid", payment.reload.status
    assert_equal "applied_after_failure", BillingEvent.find_by!(provider_event_id: "evt_late_capture").processing_result
    assert_equal "failed", retry_payment.reload.status

    # A capture on the superseded retry order is recorded for operations, never double-counted.
    post_webhook(payment_event("payment.captured", retry_payment, 300, id: "pay_double"), "evt_double_capture")
    assert_equal "failed", retry_payment.reload.status
    assert_equal "duplicate_capture", BillingEvent.find_by!(provider_event_id: "evt_double_capture").processing_result
  end

  test "payment.failed never regresses a paid payment" do
    requester, booking = accepted_booking
    payment = razorpay_payment(booking, requester)
    post_webhook(payment_event("payment.captured", payment, 200, id: "pay_ok"), "evt_paid")
    post_webhook(payment_event("payment.failed", payment, 300, id: "pay_other", status: "failed"), "evt_failed_after_paid")

    assert_equal "paid", payment.reload.status
    assert_equal "already_paid", BillingEvent.find_by!(provider_event_id: "evt_failed_after_paid").processing_result
  end

  test "checkout confirmation after a reported decline records the retried capture" do
    requester, booking = accepted_booking(requester: @user)
    payment = razorpay_payment(booking, requester)
    post_webhook(payment_event("payment.failed", payment, 100, id: "pay_declined", status: "failed"), "evt_decline")
    captured = { "id" => "pay_retry_ok", "status" => "captured", "order_id" => payment.provider_order_id, "amount" => payment.amount * 100, "currency" => "INR" }
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_KEY_SECRET"), "#{payment.provider_order_id}|pay_retry_ok")

    with_gateway(recording_gateway(payment: captured)) do
      post "/api/booking-payments/#{payment.id}/confirm", params: { orderId: payment.provider_order_id, paymentId: "pay_retry_ok", signature: }, headers: auth, as: :json
    end

    assert_response :success, response.body
    assert_equal "paid", payment.reload.status
    assert_equal "pay_retry_ok", payment.provider_payment_id
  end

  test "a full refund marks the booking payment refunded and partial refunds do not" do
    requester, booking = accepted_booking
    payment = razorpay_payment(booking, requester)
    post_webhook(payment_event("payment.captured", payment, 100, id: "pay_refundable"), "evt_refundable_paid")
    assert_equal "pay_refundable", payment.reload.provider_payment_id

    post_webhook(refund_event(payment, 200, amount: 100), "evt_partial_refund")
    assert_equal "paid", payment.reload.status
    assert_equal "partial_refund", BillingEvent.find_by!(provider_event_id: "evt_partial_refund").processing_result

    post_webhook(refund_event(payment, 300, amount: payment.amount * 100), "evt_full_refund")
    assert_equal "refunded", payment.reload.status
    assert_equal requester.id, BillingEvent.find_by!(provider_event_id: "evt_full_refund").user_id

    post_webhook(refund_event(payment, 300, amount: payment.amount * 100), "evt_full_refund")
    assert_equal true, response.parsed_body["duplicate"]
  end

  test "webhook signature is still required for the new events" do
    raw = JSON.generate(subscription_event("subscription.completed", "sub_x", 1))
    post "/api/billing/webhook/razorpay", params: raw, headers: { "CONTENT_TYPE" => "application/json", "X-Razorpay-Signature" => "bad", "X-Razorpay-Event-Id" => "evt_forged" }

    assert_response :unauthorized
    assert_not BillingEvent.exists?(provider_event_id: "evt_forged")
  end

  # 6. Entitlements

  test "shortlist capacity follows the plan and existing entries can be re-saved" do
    candidates = 21.times.map { |index| create_candidate(index) }
    candidates.first(20).each { TalentShortlist.create!(employer: @user, candidate: _1) }

    post "/api/shortlists/#{candidates.last.id}", params: {}, headers: auth, as: :json
    assert_response :payment_required
    assert_equal "PLAN_LIMIT_REACHED", response.parsed_body.fetch("code")

    post "/api/shortlists/#{candidates.first.id}", params: {}, headers: auth, as: :json
    assert_response :created

    Subscription.create!(user: @user, plan_code: "pro", provider: "internal", status: "active", current_period_end: 10.days.from_now)
    post "/api/shortlists/#{candidates.last.id}", params: {}, headers: auth, as: :json
    assert_response :created
  end

  test "active booking enquiries are capped by the plan" do
    act = create_act
    2.times { BookingRequest.create!(act:, requester: @user, event_type: "concert", city: "Pune", currency: "INR", status: "requested") }
    BookingRequest.create!(act:, requester: @user, event_type: "concert", city: "Pune", currency: "INR", status: "declined")

    post "/api/bookings", params: { actId: act.id, eventType: "concert", city: "Pune", currency: "INR" }, headers: auth, as: :json
    assert_response :payment_required
    assert_equal "PLAN_LIMIT_REACHED", response.parsed_body.fetch("code")
    assert_equal 3, BookingRequest.where(requester: @user).count
  end

  test "expired admin grants and ended trials stop granting capacity" do
    Subscription.create!(user: @user, plan_code: "studio", provider: "internal", status: "active", current_period_end: 1.minute.ago)
    Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "trialing", trial_ends_at: 1.minute.ago, provider_subscription_id: "sub_trial_over")
    assert_equal "free", Entitlements.for(@user).plan_code
    assert_equal 20, Entitlements.for(@user).limit(:shortlist)

    Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "active", trial_ends_at: 1.day.ago, provider_subscription_id: "sub_paid_after_trial")
    assert_equal "pro", Entitlements.for(@user).plan_code
    assert_equal 20, Entitlements.for(@user).limit(:bookings)

    get "/api/billing/subscription", headers: auth
    assert_equal "pro", response.parsed_body.dig("plan", "code")
  end

  private

  def auth = { "Authorization" => "Bearer #{@token}" }

  def create_user(name, role)
    user = User.create!(name:, email: "#{role}-#{SecureRandom.hex(5)}@example.com", password: "StrongPass123!", role:, status: "active")
    user.create_profile!
    token = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(token), expires_at: 1.day.from_now)
    [user, token]
  end

  def create_candidate(index)
    User.create!(name: "Candidate #{index}", email: "candidate-#{index}-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "jobseeker", status: "active", profile_complete: true).tap(&:create_profile!)
  end

  def create_act
    owner, = create_user("Act Owner", "jobseeker")
    Act.create!(owner:, name: "Hardening Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
  end

  def accepted_booking(requester: nil)
    requester ||= create_user("Buyer", "employer").first
    act = create_act
    booking = BookingRequest.create!(act:, requester:, event_type: "concert", city: "Mumbai", currency: "INR", status: "accepted")
    booking.booking_quotes.create!(created_by: act.owner, performance_fee: 10_000, travel_fee: 0, production_fee: 0, other_fee: 0, currency: "INR", deposit_percent: 50, status: "sent")
    [requester, booking]
  end

  def razorpay_payment(booking, requester)
    booking.booking_payments.create!(booking_quote: booking.booking_quotes.first, payer: requester, kind: "deposit", amount: 5_000, currency: "INR", provider: "razorpay", status: "created", provider_order_id: "order_#{SecureRandom.hex(6)}")
  end

  def in_flight_attempt(plan_code:, created_at: Time.current)
    sub = Subscription.create!(user: @user, plan_code:, provider: "razorpay", status: "pending")
    BillingAttempt.create!(user: @user, operation: "subscription_create", provider: "razorpay", idempotency_key: "#{@user.id}:subscription_create:first-tab-#{SecureRandom.hex(3)}", state: "pending", resource_type: "Subscription", resource_id: sub.id, request_payload: { plan_code: }, created_at:)
  end

  def subscription_event(name, provider_id, created_at, **entity)
    { event: name, created_at:, payload: { subscription: { entity: { id: provider_id, **entity } } } }
  end

  def payment_event(name, payment, created_at, id:, status: "captured")
    { event: name, created_at:, payload: { payment: { entity: {
      id:, order_id: payment.provider_order_id, amount: payment.amount * 100, currency: payment.currency, status:, notes: { payment_id: payment.id }
    } } } }
  end

  def refund_event(payment, created_at, amount:)
    { event: "refund.processed", created_at:, payload: {
      refund: { entity: { id: "rfnd_#{SecureRandom.hex(4)}", payment_id: payment.provider_payment_id, amount:, currency: "INR", status: "processed" } },
      payment: { entity: { id: payment.provider_payment_id, amount: payment.amount * 100, amount_refunded: amount } }
    } }
  end

  def post_webhook(payload, event_id)
    raw = JSON.generate(payload)
    signature = OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, raw)
    post "/api/billing/webhook/razorpay", params: raw, headers: { "CONTENT_TYPE" => "application/json", "X-Razorpay-Signature" => signature, "X-Razorpay-Event-Id" => event_id }
    assert_response :success, response.body
  end

  def with_gateway(gateway)
    original = RazorpayGateway.method(:new)
    RazorpayGateway.define_singleton_method(:new) { gateway }
    yield
  ensure
    RazorpayGateway.define_singleton_method(:new, original)
  end

  # Fake transport: records every call and returns canned provider entities. No network.
  def recording_gateway(responses = {})
    calls = []
    Object.new.tap do |gateway|
      gateway.define_singleton_method(:calls) { calls }
      %i[create_subscription subscription order payment create_order].each do |method|
        gateway.define_singleton_method(method) do |*args, **kwargs|
          calls << [method, *args, kwargs]
          value = responses.fetch(method) { raise "unexpected #{method}" }
          raise value if value.is_a?(Exception)
          value
        end
      end
      gateway.define_singleton_method(:cancel_subscription) do |id, **kwargs|
        calls << [:cancel_subscription, id, kwargs]
        {}
      end
    end
  end
end
