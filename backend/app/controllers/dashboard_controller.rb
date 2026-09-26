class DashboardController < ApplicationController
  def show
    return unless authenticate!
    if current_user.jobseeker?
      applications = current_user.applications
      profile = current_user.profile
      score_fields = [profile&.headline, profile&.bio, profile&.location, profile&.skills&.presence, profile&.genres&.presence, current_user.portfolio_items.exists?]
      recommended = Job.published.with_applications_count.includes(employer: :profile).order(featured: :desc, created_at: :desc).limit(6).map { |job| job.api_json.merge(fitScore: fit_score(job, profile)) }
      render json: { applications: applications.count, interviews: applications.where(status: "Interview Scheduled").count,
        saved: current_user.saved_jobs.count, profileScore: (score_fields.count(&:present?) * 100 / score_fields.length), recommendedJobs: recommended }
    else
      scope = Application.joins(:job).where(jobs: { employer_id: current_user.id })
      render json: { jobs: current_user.jobs.count, published: current_user.jobs.where(status: "published").count,
        activeJobs: current_user.jobs.where(status: %w[pending published]).count, applications: scope.count,
        shortlisted: scope.where(status: "Shortlisted").count, recentJobs: current_user.jobs.with_applications_count.includes(employer: :profile).order(updated_at: :desc).limit(8).map { _1.api_json.merge(applications: _1.applications_count) } }
    end
  end

  private

  def fit_score(job, profile)
    return 35 unless profile
    score = 35
    skills = Array(profile.skills).map { _1.to_s.downcase }
    score += [Array(job.skills).map { _1.to_s.downcase }.count { skills.include?(_1) } * 12, 35].min
    score += 15 if Array(profile.genres).map { _1.to_s.downcase }.include?(job.genre.to_s.downcase)
    # A location such as "," or " , Mumbai" has a blank first segment; blank must not match every job.
    city = profile.location.to_s.split(",").map(&:strip).find(&:present?)&.downcase
    score += 10 if city && job.location.to_s.downcase.include?(city)
    [score + (job.workplace == "remote" ? 5 : 0), 100].min
  end
end
