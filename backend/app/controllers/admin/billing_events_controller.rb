module Admin
  # Read-only ledger of processed Razorpay webhooks (for support and reconciliation).
  # The index omits raw payloads (they carry payer email/contact); `show` returns one in full.
  class BillingEventsController < BaseController
    LIMIT = 200

    def index
      scope = BillingEvent.includes(:user).order(created_at: :desc, id: :desc)
      scope = scope.where(event_type: params[:eventType]) if params[:eventType].present?
      scope = scope.where(processing_result: params[:result]) if params[:result].present?
      scope = scope.where(user_id: params[:userId]) if params[:userId].present?
      scope = scope.where("billing_events.created_at < ?", Time.zone.parse(params[:before].to_s)) if params[:before].present? && Time.zone.parse(params[:before].to_s)
      rows = scope.limit(LIMIT).to_a
      render json: { events: rows.map { summary(_1) }, nextBefore: rows.size == LIMIT ? rows.last.created_at.iso8601(6) : nil }
    end

    def show
      event = BillingEvent.includes(:user).find(params[:id])
      render json: { event: summary(event).merge(payload: event.payload) }
    end

    private

    def summary(event)
      payload = event.payload.is_a?(Hash) ? event.payload : {}
      entity = payload.dig("payload", "payment", "entity") || {}
      {
        id: event.id, provider: event.provider, providerEventId: event.provider_event_id, eventType: event.event_type,
        processingResult: event.processing_result, processedAt: event.processed_at, createdAt: event.created_at,
        userId: event.user_id, email: event.user&.email,
        subscriptionId: payload.dig("payload", "subscription", "entity", "id"),
        paymentId: entity["id"] || payload.dig("payload", "refund", "entity", "payment_id"),
        orderId: entity["order_id"], amount: entity["amount"], currency: entity["currency"]
      }
    end
  end
end
