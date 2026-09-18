module Admin
  class OperationsController < BaseController
    def audit = render(json: { logs: AuditLog.includes(:actor).order(created_at: :desc).limit(300).map { _1.attributes.merge(actorName: _1.actor&.name) } })
    def subscriptions = render(json: { subscriptions: Subscription.includes(:user).order(created_at: :desc).limit(500).map { _1.attributes.merge(name: _1.user.name, email: _1.user.email) } })
    def bookings
      rows = BookingRequest.includes(:requester, act: :owner, booking_payments: []).order(created_at: :desc).limit(500).map do |booking|
        booking.attributes.merge(actName: booking.act.name, actOwner: booking.act.owner.name, requesterName: booking.requester.name, paidAmount: booking.booking_payments.select { _1.status == "paid" }.sum(&:amount))
      end
      render json: { bookings: rows }
    end
  end
end
