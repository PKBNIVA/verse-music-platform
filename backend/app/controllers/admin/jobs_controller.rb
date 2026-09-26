module Admin
  class JobsController < BaseController
    def index = render(json: { jobs: Job.with_applications_count.includes(employer: :profile).order(created_at: :desc).limit(500).map(&:api_json) })

    def update
      return render_error("Invalid opportunity status.", :bad_request) unless %w[pending published rejected closed].include?(params[:status])
      job = Job.find(params[:id])
      job.update!(status: params[:status], moderation_note: params[:note], published_at: params[:status] == "published" ? (job.published_at || Time.current) : job.published_at)
      Notification.create!(user: job.employer, kind: "moderation", title: "Opportunity review update", body: "#{job.title}: #{job.status}", link: "/employer")
      audit!("admin.job.status", job, status: job.status)
      render json: { ok: true }
    end
  end
end
