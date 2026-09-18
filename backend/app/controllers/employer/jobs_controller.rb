module Employer
  class JobsController < ApplicationController
    def update
      return unless authenticate!("jobseeker", "employer")
      job = current_user.jobs.find(params[:id])
      return render_error("Invalid opportunity status.", :bad_request) unless %w[draft pending closed].include?(params[:status])
      job.update!(status: params[:status])
      audit!("job.status", job, status: job.status)
      render json: { ok: true }
    end
  end
end
