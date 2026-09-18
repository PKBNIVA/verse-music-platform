class ApplicationsController < ApplicationController
  def index
    return unless authenticate!("jobseeker")
    render json: { applications: current_user.applications.includes(:job).order(updated_at: :desc).map(&:api_json) }
  end

  def destroy
    return unless authenticate!("jobseeker")
    application = current_user.applications.find(params[:id])
    return render_error("A finalized application cannot be withdrawn.", :conflict) if %w[Hired Rejected].include?(application.status)
    application.destroy!
    audit!("application.withdraw", application)
    render json: { ok: true }
  end
end
