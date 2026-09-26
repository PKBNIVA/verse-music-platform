require "test_helper"

class BillingReconciliationJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Recon User", email: "recon-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "employer", status: "active")
    @now = Time.current
  end

  test "reconciles an ambiguous attempt that knows its provider id" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    attempt = create_attempt(sub, state: "ambiguous", provider_resource_id: "sub_known", updated_at: 5.minutes.ago)
    gateway = fake_gateway(subscription: { "id" => "sub_known", "status" => "created" })

    result = BillingReconciliationJob.perform_now(@now, gateway:)

    assert_equal 1, result.fetch(:reconciled)
    assert_equal "succeeded", attempt.reload.state
    assert_equal "sub_known", sub.reload.provider_subscription_id
    assert_equal 1, gateway.calls.size

    BillingReconciliationJob.perform_now(@now, gateway:)
    assert_equal 1, gateway.calls.size, "a resolved attempt is never reconciled again"
  end

  test "does not race a request that is still finishing its attempt" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    attempt = create_attempt(sub, state: "pending", provider_resource_id: "sub_fresh")
    gateway = fake_gateway(subscription: { "id" => "sub_fresh" })

    BillingReconciliationJob.perform_now(@now, gateway:)

    assert_empty gateway.calls
    assert_equal "pending", attempt.reload.state
  end

  test "provider errors are recorded and leave the attempt for the next run" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    attempt = create_attempt(sub, state: "ambiguous", provider_resource_id: "sub_flaky", updated_at: 5.minutes.ago)
    gateway = fake_gateway(subscription: RazorpayGateway::GatewayError.new("Unavailable", code: "SERVER_ERROR", http_status: 503))

    result = BillingReconciliationJob.perform_now(@now, gateway:)

    assert_equal 0, result.fetch(:reconciled)
    assert_equal "ambiguous", attempt.reload.state
    assert_equal "SERVER_ERROR", attempt.error_code
  end

  test "stale attempts without a provider id are failed and release what they reserved" do
    sub = Subscription.create!(user: @user, plan_code: "pro", provider: "razorpay", status: "pending")
    stale = create_attempt(sub, state: "ambiguous", created_at: 31.minutes.ago)
    fresh_sub = Subscription.create!(user: @user, plan_code: "studio", provider: "razorpay", status: "pending")
    fresh = create_attempt(fresh_sub, state: "pending", created_at: 10.minutes.ago)

    result = BillingReconciliationJob.perform_now(@now, gateway: fake_gateway)

    assert_equal 1, result.fetch(:stale)
    assert_equal "failed", stale.reload.state
    assert_equal "stale", stale.error_code
    assert_equal "cancelled", sub.reload.status
    assert_equal "pending", fresh.reload.state
    assert_equal "pending", fresh_sub.reload.status
  end

  test "unissued booking payments expire so a new deposit can be created" do
    payment, booking = unissued_payment(created_at: 45.minutes.ago)
    attempt = BillingAttempt.create!(user: @user, operation: "booking_order_create", provider: "razorpay", idempotency_key: "recon-order-#{SecureRandom.hex(4)}", state: "ambiguous", resource_type: "BookingPayment", resource_id: payment.id, created_at: 45.minutes.ago)
    young, = unissued_payment(created_at: 5.minutes.ago)

    BillingReconciliationJob.perform_now(@now, gateway: fake_gateway)
    BillingReconciliationJob.perform_now(@now, gateway: fake_gateway)

    assert_equal "failed", payment.reload.status
    assert_equal "failed", attempt.reload.state
    assert_equal "created", young.reload.status
    retry_payment = booking.booking_payments.create!(payer: @user, kind: "deposit", amount: 100, currency: "INR", provider: "razorpay", status: "created")
    assert retry_payment.persisted?
  end

  test "is scheduled every thirty minutes" do
    entry = Rails.application.config.good_job.cron.fetch(:billing_reconciliation)
    assert_equal "BillingReconciliationJob", entry.fetch(:class)
    assert_equal "7,37 * * * *", entry.fetch(:cron)
  end

  private

  def create_attempt(sub, state:, provider_resource_id: nil, created_at: Time.current, updated_at: created_at)
    BillingAttempt.create!(user: @user, operation: "subscription_create", provider: "razorpay", idempotency_key: "recon-#{SecureRandom.hex(6)}", state:, resource_type: "Subscription", resource_id: sub.id, provider_resource_id:, created_at:, updated_at:)
  end

  def unissued_payment(created_at:)
    owner = User.create!(name: "Act Owner", email: "owner-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    act = Act.create!(owner:, name: "Recon Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
    booking = BookingRequest.create!(act:, requester: @user, event_type: "concert", city: "Goa", currency: "INR", status: "accepted")
    payment = booking.booking_payments.create!(payer: @user, kind: "deposit", amount: 100, currency: "INR", provider: "razorpay", status: "created", created_at:)
    [payment, booking]
  end

  def fake_gateway(responses = {})
    calls = []
    Object.new.tap do |gateway|
      gateway.define_singleton_method(:calls) { calls }
      %i[subscription order].each do |method|
        gateway.define_singleton_method(method) do |id|
          calls << [method, id]
          value = responses.fetch(method) { raise "unexpected #{method}" }
          raise value if value.is_a?(Exception)
          value
        end
      end
      # Lookups for attempts without a provider id: nothing exists at Razorpay unless given.
      gateway.define_singleton_method(:subscriptions) do |**kwargs|
        calls << [:subscriptions, kwargs]
        responses.fetch(:subscriptions, { "entity" => "collection", "count" => 0, "items" => [] })
      end
      gateway.define_singleton_method(:orders_by_receipt) do |receipt|
        calls << [:orders_by_receipt, receipt]
        responses.fetch(:orders_by_receipt, { "entity" => "collection", "count" => 0, "items" => [] })
      end
    end
  end
end

# Uses real separate connections, so it cannot run inside a transactional test.
class BillingReconciliationJobLockingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    BookingPayment.where(booking_request_id: @booking&.id).delete_all
    BookingRequest.where(id: @booking&.id).delete_all
    Act.where(id: @act&.id).delete_all
    Profile.where(user_id: [@owner&.id, @user&.id]).delete_all
    User.where(id: [@owner&.id, @user&.id]).delete_all
  end

  test "a payment claimed by another worker is skipped" do
    @user = User.create!(name: "Recon Lock", email: "recon-lock-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "employer", status: "active")
    @owner = User.create!(name: "Lock Owner", email: "lock-owner-#{SecureRandom.hex(4)}@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    @act = Act.create!(owner: @owner, name: "Lock Act", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
    @booking = BookingRequest.create!(act: @act, requester: @user, event_type: "concert", city: "Goa", currency: "INR", status: "accepted")
    payment = @booking.booking_payments.create!(payer: @user, kind: "deposit", amount: 100, currency: "INR", provider: "razorpay", status: "created", created_at: 45.minutes.ago)
    locked = Queue.new
    release = Queue.new
    holder = Thread.new do
      BookingPayment.connection_pool.with_connection do
        BookingPayment.transaction do
          BookingPayment.lock.find(payment.id)
          locked << true
          release.pop
        end
      end
    end
    locked.pop

    result = BillingReconciliationJob.perform_now(Time.current, gateway: Object.new)
    release << true
    holder.join

    assert_equal 0, result.fetch(:expiredPayments)
    assert_equal "created", payment.reload.status

    assert_equal 1, BillingReconciliationJob.perform_now(Time.current, gateway: Object.new).fetch(:expiredPayments)
    assert_equal "failed", payment.reload.status
  end
end
