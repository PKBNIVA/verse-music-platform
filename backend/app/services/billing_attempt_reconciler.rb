class BillingAttemptReconciler
  def initialize(gateway: RazorpayGateway.new)
    @gateway = gateway
  end

  def call(attempt)
    raise ArgumentError, "Provider resource is not known" if attempt.provider_resource_id.blank?

    entity = case attempt.operation
    when "subscription_create" then @gateway.subscription(attempt.provider_resource_id)
    when "booking_order_create" then @gateway.order(attempt.provider_resource_id)
    else raise ArgumentError, "Unsupported billing operation"
    end

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

  def attach_resource!(attempt, entity)
    case attempt.resource_type
    when "Subscription"
      Subscription.find(attempt.resource_id).update!(provider_subscription_id: entity.fetch("id"))
    when "BookingPayment"
      payment = BookingPayment.find(attempt.resource_id)
      raise ArgumentError, "Provider order does not match the local payment" unless entity["amount"].to_i == payment.amount * 100 && entity["currency"].to_s.upcase == payment.currency
      payment.update!(provider_order_id: entity.fetch("id"))
    end
  end
end
