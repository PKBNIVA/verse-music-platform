class OrganizationsController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }

  def index
    scope = Organization.left_joins(:organization_members)
      .where("organizations.owner_id = :user_id OR organization_members.user_id = :user_id", user_id: current_user.id)
      .distinct
    render json: { organizations: scope.includes(:organization_members).map { |org| organization_json(org) } }
  end

  def create
    org = Organization.create!(owner: current_user, name: params[:name], org_type: params[:orgType], website: params[:website], city: params[:city], tax_id: params[:taxId], billing_email: params[:billingEmail], status: "active")
    org.organization_members.create!(user: current_user, role: "owner")
    render json: { id: org.id }, status: :created
  end

  def members
    org = accessible
    render json: { members: org.organization_members.includes(:user).map { |member| { id: member.user.id, name: member.user.name, email: member.user.email, role: member.role } } }
  end

  def add_member
    org = manageable
    return if performed?
    return render_error("Workspace seat limit reached.", :payment_required, "PLAN_LIMIT") if org.organization_members.count >= seat_limit(org.owner)
    user = User.find_by(email: params[:email].to_s.downcase)
    return render_error("That email must already have an active Verse account.", :not_found) unless user&.active?
    org.organization_members.find_or_create_by!(user:) { _1.role = params[:role].presence || "member" }
    Notification.create!(user:, kind: "workspace", title: "Added to workspace", body: "#{current_user.name} added you to #{org.name}.")
    render json: { ok: true }, status: :created
  end

  def remove_member
    org = manageable
    return if performed?
    return render_error("The owner cannot be removed.", :conflict) if params[:userId] == org.owner_id
    org.organization_members.where(user_id: params[:userId]).delete_all
    render json: { ok: true }
  end

  private

  def accessible
    Organization.joins(:organization_members).where(organization_members: { user_id: current_user.id }).find(params[:id])
  end

  def manageable
    org = accessible
    membership = org.organization_members.find_by(user: current_user)
    return org if %w[owner admin].include?(membership&.role)
    render_error("Not permitted.", :forbidden)
    nil
  end

  def organization_json(org)
    membership = org.organization_members.find { _1.user_id == current_user.id }
    org.attributes.merge(memberCount: org.organization_members.size, memberRole: membership&.role)
  end

  def seat_limit(owner)
    code = Subscription.where(user: owner, status: %w[active trialing]).order(created_at: :desc).pick(:plan_code) || "free"
    { "free" => 1, "pro" => 2, "studio" => 8, "enterprise" => 999 }.fetch(code, 1)
  end
end
