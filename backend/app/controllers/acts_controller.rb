class ActsController < ApplicationController
  def public_index = render(json: { acts: filtered_scope.map(&:api_json) })
  def public_show = render(json: { act: Act.includes(:act_members, owner: :profile).where(status: "active").find(params[:id]).api_json })

  def index
    return unless authenticate!
    render json: { acts: filtered_scope.map(&:api_json) }
  end

  def show
    return unless authenticate!
    render json: { act: Act.includes(:act_members, owner: :profile).find(params[:id]).api_json }
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
    member = act.act_members.create!(display_name: params[:displayName], role_name: params[:roleName], instrument: params[:instrument], member_status: params[:memberStatus].presence || "confirmed", is_leader: false, user_id: params[:userId])
    render json: { id: member.id }, status: :created
  end

  private

  def filtered_scope
    scope = Act.includes(:act_members, owner: :profile).where(status: "active").order(verified: :desc, updated_at: :desc)
    scope = scope.where("name ILIKE :q OR tagline ILIKE :q OR bio ILIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
    scope = scope.where("city ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:city])}%") if params[:city].present?
    scope.limit(100)
  end

  def act_params
    raw = params.permit(:name, :actType, :tagline, :bio, :city, :lineupSize, :minFee, :maxFee, :currency, :feeBasis, :travelRadiusKm, :travelsNationally, :travelsInternationally, :techRiderUrl, :hospitalityRiderUrl, :promoUrl, :status, genres: [], languages: [], eventTypes: []).to_h.transform_keys { _1.underscore }
    raw["currency"] ||= "INR"; raw["fee_basis"] ||= "event"; raw["status"] ||= "active"; raw
  end
end
