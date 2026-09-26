# Resolves a pending/ambiguous BillingAttempt against Razorpay.
#
# With a provider id the resource is fetched directly. Without one (the create request
# timed out or returned 5xx, so its response was lost) the resource is looked up by what
# Verse sent with it: the subscription's `notes.attempt_id`, or the order's receipt.
# ProviderResourceMissing means Razorpay has no such resource (nothing to attach).
class BillingAttemptReconciler
  class ProviderResourceMissing < StandardError; end

  LOOKUP_PAGES = 5
  LOOKUP_WINDOW = 10.minutes

  def initialize(gateway: RazorpayGateway.new)
    @gateway = gateway
  end

  def call(attempt)
    entity = attempt.provider_resource_id.present? ? fetch(attempt) : locate(attempt)

    ActiveRecord::Base.transaction do
      attach_resource!(attempt, entity)
      attempt.succeed!(provider_resource_id: entity.fetch("id"), response_payload: entity)
    end
    attempt
  rescue RazorpayGateway::GatewayError => error
    attempt.update!(error_code: error.code, error_message: error.message, last_attempted_at: Time.current)
    raise
  end

  private

  def fetch(attempt)
    case attempt.operation
    when "subscription_create" then @gateway.subscription(attempt.provider_resource_id)
    when "booking_order_create" then @gateway.order(attempt.provider_resource_id)
    else raise ArgumentError, "Unsupported billing operation"
    end
  end

  def locate(attempt)
    found = case attempt.operation
    when "subscription_create" then locate_subscription(attempt)
    when "booking_order_create" then locate_order(attempt)
    else raise ArgumentError, "Unsupported billing operation"
    end
    found or raise ProviderResourceMissing, "Razorpay has no #{attempt.operation.delete_suffix("_create")} for attempt #{attempt.id}"
  end

  def locate_subscription(attempt)
    from = attempt.created_at - LOOKUP_WINDOW
    to = attempt.created_at + BillingAttempt::STALE_AFTER + LOOKUP_WINDOW
    LOOKUP_PAGES.times do |page|
      items = Array(@gateway.subscriptions(from:, to:, count: 100, skip: page * 100)["items"])
      match = items.find { |item| item.dig("notes", "attempt_id").to_s == attempt.id.to_s }
      return match if match
      return nil if items.size < 100
    end
    nil
  end

  def locate_order(attempt)
    items = Array(@gateway.orders_by_receipt(BookingPayment.receipt_for(attempt.resource_id))["items"])
    items.find { |item| item.dig("notes", "attempt_id").to_s == attempt.id.to_s }
  end

  def attach_resource!(attempt, entity)
    case attempt.resource_type
    when "Subscription"
      sub = Subscription.find(attempt.resource_id)
      raise ArgumentError, "Subscription was released before reconciliation" if sub.status == "cancelled" && sub.provider_subscription_id.blank?

      sub.update!(provider_subscription_id: entity.fetch("id"))
    when "BookingPayment"
      payment = BookingPayment.find(attempt.resource_id)
      raise ArgumentError, "Provider order does not match the local payment" unless entity["amount"].to_i == payment.amount * 100 && entity["currency"].to_s.upcase == payment.currency
      raise ArgumentError, "Payment was released before reconciliation" if payment.status == "failed" && payment.provider_order_id.blank?

      payment.update!(provider_order_id: entity.fetch("id"))
    end
  end
end
