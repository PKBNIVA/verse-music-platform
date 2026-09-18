module Admin
  class OperationsController < BaseController
    def audit = render(json: { logs: AuditLog.includes(:actor).order(created_at: :desc).limit(300) })
    def subscriptions = render(json: { subscriptions: Subscription.includes(:user).order(created_at: :desc).limit(500) })
    def bookings = render(json: { bookings: [] })
  end
end
