class SearchController < ApplicationController
  SYNONYMS = {
    "sound guy" => ["foh engineer", "live sound engineer", "audio engineer"],
    "singer" => ["vocalist", "playback singer"],
    "guitar player" => ["guitarist"],
    "bass player" => ["bassist"],
    "drum player" => ["drummer"],
    "music director" => ["musical director", "composer"],
    "tech director" => ["technical director"],
    "roadie" => ["backline technician", "stage technician"]
  }.freeze
  RESULT_TYPES = %w[jobs talent acts samples].freeze

  def index
    terms = expanded_terms(params[:q].to_s.strip)
    return render json: search_response([]) if terms.empty?

    requested_type = RESULT_TYPES.include?(params[:type]) ? params[:type] : nil
    results = []
    results.concat(job_results(terms)) if requested_type.nil? || requested_type == "jobs"
    results.concat(talent_results(terms)) if requested_type.nil? || requested_type == "talent"
    results.concat(act_results(terms)) if requested_type.nil? || requested_type == "acts"
    results.concat(sample_results(terms)) if requested_type.nil? || requested_type == "samples"
    render json: search_response(results.first(60), terms)
  end

  def status = render(json: status_payload)

  private

  def expanded_terms(query)
    [query, *SYNONYMS.select { |key, _| query.downcase.include?(key) }.values.flatten].reject(&:blank?).uniq
  end

  def job_results(terms)
    sql = terms.map { "(jobs.title ILIKE ? OR jobs.company ILIKE ? OR jobs.description ILIKE ? OR jobs.skills::text ILIKE ?)" }.join(" OR ")
    values = terms.flat_map { Array.new(4, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    Job.published.includes(:employer).where(sql, *values).order(featured: :desc, created_at: :desc).limit(30).map do |job|
      { type: "jobs", id: job.id, demo: SyntheticQa::Demo.user?(job.employer), url: "/opportunities/#{job.id}", title: job.title,
        subtitle: [job.company, job.location].compact.join(" · "), description: job.description,
        tags: [job.opportunity_kind, job.function_area, job.workplace, job.genre, *job.skills].compact.uniq }
    end
  end

  def talent_results(terms)
    sql = terms.map { "(users.name ILIKE ? OR profiles.headline ILIKE ? OR profiles.bio ILIKE ? OR profiles.skills::text ILIKE ? OR profiles.roles::text ILIKE ?)" }.join(" OR ")
    values = terms.flat_map { Array.new(5, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    scope = User.discoverable_talent.joins(:profile).preload(:profile)
    scope = SyntheticQa::Demo.publicly_listed(scope) unless synthetic_viewer?
    scope.where(sql, *values).limit(30).map do |user|
      profile = user.profile
      { type: "talent", id: user.id, demo: SyntheticQa::Demo.user?(user), url: "/professionals/#{user.id}", title: user.name,
        subtitle: [profile.headline, profile.location].compact.join(" · "), description: profile.bio,
        tags: [*profile.roles, *profile.skills, *profile.genres, *profile.instruments].compact.uniq }
    end
  end

  def act_results(terms)
    sql = terms.map { "(acts.name ILIKE ? OR acts.tagline ILIKE ? OR acts.bio ILIKE ? OR acts.genres::text ILIKE ?)" }.join(" OR ")
    values = terms.flat_map { Array.new(4, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    Act.includes(:owner).where(status: "active").where(sql, *values).order(verified: :desc, updated_at: :desc).limit(30).map do |act|
      { type: "acts", id: act.id, demo: SyntheticQa::Demo.user?(act.owner), url: "/acts/#{act.id}", title: act.name,
        subtitle: [act.act_type, act.city].compact.join(" · "), description: act.tagline.presence || act.bio,
        tags: [act.act_type, *act.genres, *act.event_types].compact.uniq }
    end
  end

  def sample_results(terms)
    sql = terms.map { "(portfolio_items.title ILIKE ? OR portfolio_items.description ILIKE ? OR portfolio_items.tags::text ILIKE ? OR portfolio_items.genres::text ILIKE ? OR portfolio_items.roles::text ILIKE ?)" }.join(" OR ")
    values = terms.flat_map { Array.new(5, "%#{ActiveRecord::Base.sanitize_sql_like(_1)}%") }
    scope = PortfolioItem.joins(user: :profile).includes(:user)
      .where(visibility: "public", users: { status: "active", profile_complete: true })
    scope = SyntheticQa::Demo.publicly_listed(scope) unless synthetic_viewer?
    scope.where(sql, *values).order(featured: :desc, updated_at: :desc).limit(30).map do |item|
      { type: "samples", id: item.id, demo: SyntheticQa::Demo.user?(item.user), url: "/professionals/#{item.user_id}", title: item.title,
        subtitle: [item.user.name, item.credited_as].compact.join(" · "), description: item.description,
        tags: [item.kind, *item.tags, *item.genres, *item.roles, *item.instruments].compact.uniq }
    end
  end

  # Synthetic QA accounts are hidden from real users (except badged demo-* batches) but remain
  # discoverable to other synthetic accounts.
  def synthetic_viewer? = current_user&.synthetic_batch.present?

  def search_response(results, terms = [])
    { results:, interpretedAs: terms.map(&:downcase), provider: "postgresql", status: status_payload }
  end

  def status_payload = { provider: "postgresql", healthy: true, fallback: false }
end
