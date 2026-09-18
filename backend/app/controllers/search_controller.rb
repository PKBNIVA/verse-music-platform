class SearchController < ApplicationController
  def index
    query = params[:q].to_s.strip
    escaped = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    jobs = Job.published.where("title ILIKE :q OR company ILIKE :q OR description ILIKE :q", q: escaped).includes(:employer).limit(30).map { _1.api_json.merge(resultType: "job") }
    talent = User.joins(:profile).where(role: "jobseeker", status: "active", profile_complete: true).where("users.name ILIKE :q OR profiles.headline ILIKE :q OR profiles.bio ILIKE :q", q: escaped).limit(30).map { public_user(_1).merge(resultType: "talent") }
    results = params[:type] == "jobs" ? jobs : params[:type] == "talent" ? talent : jobs + talent
    render json: { results:, interpretedAs: [query.downcase].reject(&:blank?), status: status_payload }
  end

  def status = render(json: status_payload)

  private

  def status_payload = { provider: "postgresql", healthy: true, fallback: false }
end
