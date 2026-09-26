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
    skills = profile.skills.map(&:downcase)
    score += [job.skills.map(&:downcase).count { skills.include?(_1) } * 12, 35].min
    score += 15 if profile.genres.map(&:downcase).include?(job.genre.to_s.downcase)
    score += 10 if profile.location.present? && job.location.to_s.downcase.include?(profile.location.split(",").first.downcase)
    [score + (job.workplace == "remote" ? 5 : 0), 100].min
  end
end
