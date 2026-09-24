module Admin
  class UsersController < BaseController
    def index = render(json: { users: User.includes(:profile).order(created_at: :desc).limit(500).map { public_user(_1).merge("createdAt" => _1.created_at) } })

    def update
      return render_error("You cannot change your own admin status.", :conflict) if params[:id] == current_user.id
      return render_error("Invalid user status.", :bad_request) unless %w[active suspended pending].include?(params[:status])
      user = User.find(params[:id])
      user.update!(status: params[:status])
      user.sessions.delete_all if user.suspended?
      audit!("admin.user.status", user, status: user.status)
      render json: { ok: true }
    end

    def grant_plan
      return render_error("Invalid plan.", :bad_request) unless %w[pro studio enterprise].include?(params[:planCode])
      user = User.find(params[:id])
      Subscription.where(user:, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
      subscription = Subscription.create!(user:, plan_code: params[:planCode], provider: "internal", status: "active", current_period_start: Time.current, current_period_end: params.fetch(:days, 30).to_i.clamp(1, 366).days.from_now)
      audit!("admin.plan.grant", subscription, planCode: subscription.plan_code)
      render json: { id: subscription.id }, status: :created
    end
  end
end
