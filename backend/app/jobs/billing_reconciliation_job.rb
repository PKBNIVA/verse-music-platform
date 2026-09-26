# Resolves billing work that a crashed or timed-out request left behind.
#
# 1. Pending/ambiguous attempts that know their provider id are reconciled against Razorpay.
# 2. Attempts that never learned a provider id (the create response was lost) are looked up
#    at Razorpay by the attempt id sent in notes/receipt and attached when found.
#    Once older than BillingAttempt::STALE_AFTER and confirmed absent (or when Razorpay is not
#    configured) they are failed together with the local resource they reserved. The browser
#    never received a provider id for them, so nothing can be authorised or paid against them.
# 3. Razorpay booking payments stuck in `created` without an order are failed so the partial
#    unique index on active deposits no longer blocks a retry.
#
# Every row is claimed with FOR UPDATE SKIP LOCKED and its state is re-checked under the lock,
# so overlapping runs (or a concurrent request) never process the same row twice.
class BillingReconciliationJob < ApplicationJob
  queue_as :scheduled

  # Leave very recent attempts to the request that is still finishing them.
  SETTLE_AFTER = 2.minutes
  BATCH = 200

  def perform(now = Time.current, gateway: nil)
    @now = now
    @gateway = gateway
    @recovered = 0
    reconciled = reconcile_known
    stale = resolve_unknown
    { reconciled: reconciled + @recovered, stale:, expiredPayments: expire_unissued_payments }
  end

  private

  def reconcile_known
    return 0 unless @gateway || RazorpayConfig.usable?

    ids = BillingAttempt.unresolved.where.not(provider_resource_id: nil).where("updated_at <= ?", @now - SETTLE_AFTER).order(:created_at).limit(BATCH).pluck(:id)
    ids.count do |id|
      claim(BillingAttempt, id) do |attempt|
        next false unless %w[pending ambiguous].include?(attempt.state) && attempt.provider_resource_id.present?

        reconciler.call(attempt)
        true
      rescue RazorpayGateway::GatewayError, ArgumentError, ActiveRecord::RecordNotFound => error
        attempt.update!(error_code: error.is_a?(RazorpayGateway::GatewayError) ? error.code : "reconcile_failed", error_message: error.message.first(500), last_attempted_at: @now)
        Rails.logger.warn("billing reconciliation failed attempt=#{attempt.id} error=#{error.class}")
        ErrorReporter.capture(error, tags: { source: "billing_reconciliation_failed" }, level: :warning, billingAttemptId: attempt.id)
        false
      end
    end
  end

  # Returns the number of attempts failed as stale; recovered ones are counted in @recovered.
  def resolve_unknown
    cutoff = @now - BillingAttempt::STALE_AFTER
    lookup = @gateway || RazorpayConfig.usable?
    scope = BillingAttempt.unresolved.where(provider_resource_id: nil)
    scope = lookup ? scope.where("updated_at <= ? OR created_at <= ?", @now - SETTLE_AFTER, cutoff) : scope.where("created_at <= ?", cutoff)
    ids = scope.order(:created_at).limit(BATCH).pluck(:id)
    ids.count do |id|
      claim(BillingAttempt, id) do |attempt|
        next false unless %w[pending ambiguous].include?(attempt.state) && attempt.provider_resource_id.blank?

        if lookup
          begin
            reconciler.call(attempt)
            @recovered += 1
            next false
          rescue BillingAttemptReconciler::ProviderResourceMissing
            # Confirmed absent at Razorpay: fail it once it is old enough.
          rescue RazorpayGateway::GatewayError, ArgumentError, ActiveRecord::RecordNotFound => error
            attempt.update!(error_code: error.is_a?(RazorpayGateway::GatewayError) ? error.code : "reconcile_failed", error_message: error.message.first(500), last_attempted_at: @now)
            ErrorReporter.capture(error, tags: { source: "billing_reconciliation_failed" }, level: :warning, billingAttemptId: attempt.id)
            next false if error.is_a?(RazorpayGateway::GatewayError)
          end
        end
        next false unless attempt.created_at <= cutoff

        attempt.mark_stale!(now: @now)
        release_resource!(attempt)
        true
      end
    end
  end

  def expire_unissued_payments
    cutoff = @now - BookingPayment::UNISSUED_ORDER_TTL
    ids = BookingPayment.where(provider: "razorpay", status: "created", provider_order_id: nil).where("created_at <= ?", cutoff).order(:created_at).limit(BATCH).pluck(:id)
    ids.count do |id|
      claim(BookingPayment, id) { |payment| payment.expire_unissued!(now: @now) }
    end
  end

  def release_resource!(attempt)
    case attempt.resource_type
    when "Subscription"
      Subscription.where(id: attempt.resource_id, provider: "razorpay", status: "pending", provider_subscription_id: nil).update_all(status: "cancelled", updated_at: @now)
    when "BookingPayment"
      payment = BookingPayment.find_by(id: attempt.resource_id)
      payment.update!(status: "failed") if payment && payment.status == "created" && payment.provider_order_id.blank?
    end
  end

  # Runs the block with the row locked, or skips it when another worker holds it.
  def claim(model, id)
    model.transaction do
      record = model.lock("FOR UPDATE SKIP LOCKED").find_by(id:)
      record ? yield(record) : false
    end
  end

  def reconciler = @reconciler ||= BillingAttemptReconciler.new(gateway: @gateway || RazorpayGateway.new)
end
