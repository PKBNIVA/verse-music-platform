class DashboardController < ApplicationController
  def show
    return unless authenticate!
    if current_user.jobseeker?
      render json: { stats: { applications: current_user.applications.count, savedJobs: current_user.saved_jobs.count, portfolioItems: current_user.portfolio_items.count, unreadNotifications: current_user.notifications.where(read_at: nil).count }, recentApplications: current_user.applications.includes(:job).order(updated_at: :desc).limit(5).map(&:api_json) }
    else
      render json: { stats: { jobs: current_user.jobs.count, liveJobs: current_user.jobs.published.count, applications: Application.joins(:job).where(jobs: { employer_id: current_user.id }).count, unreadNotifications: current_user.notifications.where(read_at: nil).count } }
    end
  end
end
