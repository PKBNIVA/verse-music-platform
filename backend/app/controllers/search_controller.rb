class SearchController < ApplicationController
  SYNONYMS = { "sound guy" => ["foh engineer", "live sound engineer", "audio engineer"], "singer" => ["vocalist", "playback singer"], "guitar player" => ["guitarist"], "bass player" => ["bassist"], "drum player" => ["drummer"], "music director" => ["musical director", "composer"], "tech director" => ["technical director"], "roadie" => ["backline technician", "stage technician"] }.freeze
  def index
    query = params[:q].to_s.strip
    terms = [query, *SYNONYMS.select { |key, _| query.downcase.include?(key) }.values.flatten].reject(&:blank?).uniq
    return render json: { results: [], interpretedAs: [], status: status_payload } if terms.empty?
    job_sql = terms.map { "(jobs.title ILIKE ? OR jobs.company ILIKE ? OR jobs.description ILIKE ? OR jobs.skills::text ILIKE ?)" }.join(" OR ")
    values = terms.flat_map { Array.new(4, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    jobs = Job.published.where(job_sql, *values).includes(:employer).limit(30).map { _1.api_json.merge(resultType: "job") }
    talent_sql = terms.map { "(users.name ILIKE ? OR profiles.headline ILIKE ? OR profiles.bio ILIKE ? OR profiles.skills::text ILIKE ? OR profiles.roles::text ILIKE ?)" }.join(" OR ")
    talent_values = terms.flat_map { Array.new(5, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    talent = User.joins(:profile).where(role: "jobseeker", status: "active", profile_complete: true).where(talent_sql, *talent_values).limit(30).map { public_profile(_1).merge(resultType: "talent") }
    results = params[:type] == "jobs" ? jobs : params[:type] == "talent" ? talent : jobs + talent
    render json: { results:, interpretedAs: terms.map(&:downcase), status: status_payload }
  end

  def status = render(json: status_payload)

  private

  def status_payload = { provider: "postgresql", healthy: true, fallback: false }
end
