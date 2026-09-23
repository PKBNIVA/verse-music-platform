class TalentController < ApplicationController
  def public_index
    scope = public_scope
    scope = filter(scope)
    render json: { talent: scope.limit(100).map { public_profile(_1) } }
  end

  def public_show
    candidate = public_scope.find(params[:id])
    render json: { professional: public_profile(candidate), portfolio: candidate.portfolio_items.where(visibility: "public").order(featured: :desc, sort_order: :asc).map(&:api_json) }
  end

  def index
    return unless authenticate!("jobseeker", "employer")
    shortlisted = TalentShortlist.where(employer: current_user).pluck(:candidate_id).to_set
    render json: { candidates: filter(public_scope).limit(100).map { public_profile(_1).merge(shortlisted: shortlisted.include?(_1.id)) } }
  end

  def show
    return unless authenticate!("jobseeker", "employer")
    candidate = public_scope.find(params[:id])
    RecentActivity.create!(user: current_user, kind: "profile_view", entity_id: candidate.id, label: candidate.name)
    render json: { candidate: public_profile(candidate), portfolio: candidate.portfolio_items.where(visibility: "public").map(&:api_json) }
  end

  def compare
    return unless authenticate!("jobseeker", "employer")
    ids = params[:ids].to_s.split(",").uniq.first(4)
    return render_error("Choose at least two professionals to compare.", :bad_request) if ids.length < 2
    professionals = public_scope.where(id: ids).map { |candidate| public_profile(candidate).merge(portfolio: candidate.portfolio_items.where(visibility: "public").limit(8).map(&:api_json), availability: AvailabilityWindow.where(user: candidate).where("end_at > ?", Time.current).limit(5)) }
    render json: { professionals: }
  end

  def shortlist
    return unless authenticate!("jobseeker", "employer")
    TalentShortlist.find_or_create_by!(employer: current_user, candidate: public_scope.find(params[:id])) { _1.note = params[:note] }
    render json: { ok: true }, status: :created
  end

  def unshortlist
    return unless authenticate!("jobseeker", "employer")
    TalentShortlist.where(employer: current_user, candidate_id: params[:id]).delete_all
    render json: { ok: true }
  end

  def recent
    return unless authenticate!("jobseeker", "employer")
    render json: { items: RecentActivity.where(user: current_user).order(created_at: :desc).limit(30).as_json.map { _1.transform_keys { |key| key.camelize(:lower) } } }
  end

  def clear_recent
    return unless authenticate!("jobseeker", "employer")
    RecentActivity.where(user: current_user).delete_all
    render json: { ok: true }
  end

  def employers
    return unless authenticate!
    render json: { employers: User.employer.active.includes(:profile).map { public_employer(_1) } }
  end

  private

  def public_scope = User.jobseeker.active.where(profile_complete: true).includes(:profile, :portfolio_items)

  def filter(scope)
    if params[:q].present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      scope = scope.joins(:profile).where("users.name ILIKE :q OR profiles.headline ILIKE :q OR profiles.bio ILIKE :q", q:)
    end
    scope = scope.joins(:profile).where("profiles.location ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:location])}%") if params[:location].present?
    scope = scope.joins(:profile).where("profiles.roles::text ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:role])}%") if params[:role].present?
    scope = scope.joins(:profile).where("profiles.instruments::text ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:instrument])}%") if params[:instrument].present?
    scope = scope.joins(:profile).where(profiles: { verified: true }) if params[:verified] == "true"
    scope = scope.joins(:profile).where(profiles: { remote_recording: true }) if params[:remoteRecording] == "true"
    scope
  end
end
