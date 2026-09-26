module Admin
  class UsersController < BaseController
    def index = render(json: { users: User.includes(:profile).order(created_at: :desc).limit(500).map { public_user(_1).merge("createdAt" => _1.created_at) } })

    def update
      return render_error("You cannot change your own admin status.", :conflict) if params[:id] == current_user.id
      return render_error("Invalid user status.", :bad_request) unless %w[active suspended pending].include?(params[:status])
      user = User.find(params[:id])
      user.update!(status: params[:status])
      user.sessions.delete_all unless user.active?
      audit!("admin.user.status", user, status: user.status)
      render json: { ok: true }
    end

    def grant_plan
      return render_error("Invalid plan.", :bad_request) unless %w[pro studio enterprise].include?(params[:planCode])
      days = params.fetch(:days, 30)
      return render_error("Days must be a whole number between 1 and 366.", :bad_request) unless days.to_s.match?(/\A\d+\z/) && days.to_i.between?(1, 366)
      user = User.find(params[:id])
      return render_error("Plans can only be granted to professional or organization accounts.", :unprocessable_entity) if user.admin?
      Subscription.where(user:, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
      subscription = Subscription.create!(user:, plan_code: params[:planCode], provider: "internal", status: "active", current_period_start: Time.current, current_period_end: days.to_i.days.from_now)
      audit!("admin.plan.grant", subscription, planCode: subscription.plan_code)
      render json: { id: subscription.id }, status: :created
    end
  end
end
