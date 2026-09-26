class ApplicationsController < ApplicationController
  def index
    return unless authenticate!("jobseeker")
    render json: { applications: current_user.applications.includes(:job).order(updated_at: :desc).limit(200).map { candidate_json(_1) } }
  end

  def destroy
    return unless authenticate!("jobseeker")
    application = current_user.applications.find(params[:id])
    return render_error("A finalized application cannot be withdrawn.", :conflict) if %w[Hired Rejected].include?(application.status)
    application.destroy!
    audit!("application.withdraw", application)
    render json: { ok: true }
  end

  private

  # The employer's private rating and note about a candidate are hiring-team data only.
  EMPLOYER_ONLY_FIELDS = %w[recruiter_rating recruiter_note recruiterRating recruiterNote].freeze

  def candidate_json(application)
    application.api_json.stringify_keys.except(*EMPLOYER_ONLY_FIELDS)
  end
end
