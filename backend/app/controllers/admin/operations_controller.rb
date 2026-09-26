module Admin
  class OperationsController < BaseController
    def audit = render(json: { logs: AuditLog.includes(:actor).order(created_at: :desc).limit(300).map { _1.attributes.merge(actorName: _1.actor&.name) } })
    def subscriptions = render(json: { subscriptions: Subscription.includes(:user).order(created_at: :desc).limit(500).map { _1.attributes.merge(name: _1.user.name, email: _1.user.email) } })
    def billing_attempts = render(json: { attempts: BillingAttempt.includes(:user).order(created_at: :desc).limit(500).map { _1.attributes.merge(email: _1.user.email) } })

    def reconcile_billing_attempt
      attempt = BillingAttempt.find(params[:id])
      BillingAttemptReconciler.new.call(attempt)
      audit!("admin.billing_attempt.reconcile", attempt)
      render json: { attempt: }
    rescue BillingAttemptReconciler::ProviderResourceMissing => error
      render_error(error.message, :not_found, "PROVIDER_RESOURCE_MISSING")
    rescue ArgumentError => error
      render_error(error.message, :conflict)
    rescue RazorpayGateway::GatewayError => error
      render_error(error.message, :bad_gateway)
    end
    def bookings
      rows = BookingRequest.includes(:requester, act: :owner, booking_payments: []).order(created_at: :desc).limit(500).map do |booking|
        booking.attributes.merge(actName: booking.act.name, actOwner: booking.act.owner.name, requesterName: booking.requester.name, paidAmount: booking.booking_payments.select { _1.status == "paid" }.sum(&:amount))
      end
      render json: { bookings: rows }
    end
  end
end
