require "test_helper"

class FinancialIntegrityTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "financial-integrity-test-secret"

  test "subscription webhooks cannot regress or resurrect provider state" do
    user = create_user("Billing Owner", "billing-owner@example.com", "employer")
    subscription = Subscription.create!(user:, plan_code: "pro", provider: "razorpay", status: "pending", provider_subscription_id: "sub_integrity")

    with_webhook_secret do
      post_webhook(subscription_event("subscription.activated", subscription, 200), "evt_active")
      assert_response :success
      assert_equal "active", subscription.reload.status

      post_webhook(subscription_event("subscription.pending", subscription, 100), "evt_stale_pending")
      assert_response :success
      assert_equal "active", subscription.reload.status
      assert_equal "stale", BillingEvent.find_by!(provider_event_id: "evt_stale_pending").processing_result

      post_webhook(subscription_event("subscription.cancelled", subscription, 300), "evt_cancelled")
      assert_equal "cancelled", subscription.reload.status

      post_webhook(subscription_event("subscription.charged", subscription, 250), "evt_old_charge")
      assert_equal "cancelled", subscription.reload.status
    end
  end

  test "captured payment is validated, locked, and idempotent" do
    payment = create_razorpay_payment

    with_webhook_secret do
      invalid = payment_event(payment, 100, amount: payment.amount * 100 + 1)
      post_webhook(invalid, "evt_wrong_amount")
      assert_response :success
      assert_equal "created", payment.reload.status
      assert_equal "invalid_amount", BillingEvent.find_by!(provider_event_id: "evt_wrong_amount").processing_result

      valid = payment_event(payment, 200)
      post_webhook(valid, "evt_capture")
      assert_response :success
      assert_equal "paid", payment.reload.status
      assert_equal "pay_integrity", payment.provider_payment_id

      post_webhook(valid, "evt_capture")
      assert_response :success
      assert_equal true, response.parsed_body.fetch("duplicate")
      assert_equal 1, BillingEvent.where(provider_event_id: "evt_capture").count
    end
  end

  test "failed payment cannot be resurrected by a late capture" do
    payment = create_razorpay_payment
    payment.update!(status: "failed")

    with_webhook_secret do
      post_webhook(payment_event(payment, 200), "evt_failed_capture")
      assert_response :success
    end

    assert_equal "failed", payment.reload.status
    assert_equal "invalid_transition", BillingEvent.find_by!(provider_event_id: "evt_failed_capture").processing_result
  end

  test "malformed signed webhook is rejected without an event" do
    with_webhook_secret { post_webhook("{", "evt_bad_json", encode: false) }
    assert_response :bad_request
    assert_not BillingEvent.exists?(provider_event_id: "evt_bad_json")
  end

  test "booking transitions recheck state while holding the row lock" do
    requester, owner, booking = create_booking

    booking.transition_to!("negotiating", actor: requester)
    assert_raises(BookingRequest::InvalidTransition) { booking.transition_to!("viewed", actor: owner) }
    assert_equal "negotiating", booking.reload.status
  end

  test "database constraints reject invalid financial values" do
    payment = create_razorpay_payment

    assert_raises(ActiveRecord::StatementInvalid) do
      BookingPayment.transaction(requires_new: true) do
        BookingPayment.where(id: payment.id).update_all(amount: 0)
      end
    end
    assert_equal payment.amount, payment.reload.amount
  end

  private

  def create_user(name, email, role)
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active").tap(&:create_profile!)
  end

  def create_booking
    owner = create_user("Act Owner", "act-owner-#{SecureRandom.hex(3)}@example.com", "jobseeker")
    requester = create_user("Event Buyer", "event-buyer-#{SecureRandom.hex(3)}@example.com", "employer")
    act = Act.create!(owner:, name: "Integrity Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
    booking = BookingRequest.create!(act:, requester:, event_type: "concert", city: "Mumbai", currency: "INR", status: "requested")
    [requester, owner, booking]
  end

  def create_razorpay_payment
    requester, owner, booking = create_booking
    quote = booking.booking_quotes.create!(created_by: owner, performance_fee: 10_000, travel_fee: 0, production_fee: 0, other_fee: 0, currency: "INR", deposit_percent: 50, status: "sent")
    booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", amount: 5_000, currency: "INR", provider: "razorpay", status: "created", provider_order_id: "order_#{SecureRandom.hex(6)}")
  end

  def subscription_event(name, subscription, created_at)
    { event: name, created_at:, payload: { subscription: { entity: { id: subscription.provider_subscription_id } } } }
  end

  def payment_event(payment, created_at, amount: payment.amount * 100)
    {
      event: "payment.captured", created_at:,
      payload: { payment: { entity: {
        id: "pay_integrity", order_id: payment.provider_order_id, amount:, currency: payment.currency,
        status: "captured", notes: { payment_id: payment.id }
      } } }
    }
  end

  def post_webhook(payload, event_id, encode: true)
    raw = encode ? JSON.generate(payload) : payload
    signature = OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, raw)
    post "/api/billing/webhook/razorpay", params: raw,
      headers: { "CONTENT_TYPE" => "application/json", "X-Razorpay-Signature" => signature, "X-Razorpay-Event-Id" => event_id }
  end

  def with_webhook_secret
    previous = ENV["RAZORPAY_WEBHOOK_SECRET"]
    ENV["RAZORPAY_WEBHOOK_SECRET"] = WEBHOOK_SECRET
    yield
  ensure
    ENV["RAZORPAY_WEBHOOK_SECRET"] = previous
  end
end
