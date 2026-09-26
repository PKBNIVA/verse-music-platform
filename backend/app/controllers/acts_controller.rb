class ActsController < ApplicationController
  # Only "confirmed" exists today: public lineups show confirmed members and no flow sets another status.
  MEMBER_STATUSES = %w[confirmed].freeze

  def public_index = render(json: { acts: filtered_scope.map(&:public_json) })
  def public_show = render(json: { act: Act.includes(:act_members, owner: :profile).where(status: "active").find(params[:id]).public_json })

  def index
    return unless authenticate!
    render json: { acts: filtered_scope.map(&:public_json) }
  end

  def show
    return unless authenticate!
    scope = Act.includes(:act_members, owner: :profile)
    scope = scope.where("acts.status = ? OR acts.owner_id = ?", "active", current_user.id) unless current_user.admin?
    act = scope.find(params[:id])
    render json: { act: act.owner_id == current_user.id || current_user.admin? ? act.api_json : act.public_json }
  end

  def mine
    return unless authenticate!("jobseeker", "employer")
    render json: { acts: current_user.owned_acts.includes(:act_members).order(updated_at: :desc).map(&:api_json) }
  end

  def create
    return unless authenticate!("jobseeker", "employer")
    act = current_user.owned_acts.create!(act_params)
    act.act_members.create!(display_name: current_user.name, role_name: params[:leaderRole].presence || params[:ownerRole].presence || "Leader", is_leader: true, member_status: "confirmed", user: current_user)
    audit!("act.create", act)
    render json: { id: act.id, act: act.reload.api_json }, status: :created
  end

  def add_member
    return unless authenticate!("jobseeker", "employer")
    act = current_user.owned_acts.find(params[:id])
    status = params[:memberStatus].presence || "confirmed"
    return render_error("Invalid member status.", :bad_request, "INVALID_MEMBER_STATUS") unless MEMBER_STATUSES.include?(status)
    linked_user = nil
    if params[:userId].present?
      # Only active professionals can be linked to a lineup; anything else is indistinguishable from unknown.
      linked_user = User.jobseeker.active.find_by(id: params[:userId].to_s)
      return render_error("Professional not found.", :not_found) unless linked_user
      return render_error("That professional is already in this lineup.", :conflict) if act.act_members.exists?(user_id: linked_user.id)
    end
    member = act.act_members.create!(display_name: params[:displayName], role_name: params[:roleName], instrument: params[:instrument], member_status: status, is_leader: false, user: linked_user)
    render json: { id: member.id }, status: :created
  end

  def update
    return unless authenticate!("jobseeker", "employer")
    act = current_user.owned_acts.find(params[:id])
    act.update!(act_params)
    audit!("act.update", act)
    render json: { act: act.reload.api_json }
  end

  def destroy
    return unless authenticate!("jobseeker", "employer")
    act = current_user.owned_acts.find(params[:id])
    act.update!(status: "inactive")
    audit!("act.deactivate", act)
    render json: { ok: true }
  end

  def remove_member
    return unless authenticate!("jobseeker", "employer")
    act = current_user.owned_acts.find(params[:id])
    member = act.act_members.find(params[:member_id])
    return render_error("The act leader cannot be removed.", :conflict) if member.is_leader?
    member.destroy!
    render json: { ok: true }
  end

  private

  def filtered_scope
    scope = Act.includes(:act_members, owner: :profile).where(status: "active").order(verified: :desc, updated_at: :desc)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.left_outer_joins(:act_members).where(<<~SQL.squish, q:).distinct
        acts.name ILIKE :q OR acts.tagline ILIKE :q OR acts.bio ILIKE :q OR
        acts.act_type ILIKE :q OR acts.genres::text ILIKE :q OR acts.event_types::text ILIKE :q OR
        act_members.role_name ILIKE :q OR act_members.instrument ILIKE :q
      SQL
    end
    scope = scope.where("acts.city ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:city])}%") if params[:city].present?
    scope.limit(100)
  end

  def act_params
    raw = params.permit(:name, :actType, :tagline, :bio, :city, :lineupSize, :minFee, :maxFee, :currency, :feeBasis, :travelRadiusKm, :travelsNationally, :travelsInternationally, :techRiderUrl, :hospitalityRiderUrl, :promoUrl, :status, genres: [], languages: [], eventTypes: []).to_h.transform_keys { _1.underscore }
    raw["currency"] ||= "INR"; raw["fee_basis"] ||= "event"; raw["status"] ||= "active"; raw
  end
end
