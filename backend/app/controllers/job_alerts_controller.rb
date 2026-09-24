class JobAlertsController < ApplicationController
  before_action -> { authenticate!("jobseeker") }

  def index = render(json: { alerts: current_user.job_alerts.order(created_at: :desc) })

  def create
    alert = current_user.job_alerts.create!(alert_params)
    render json: { id: alert.id }, status: :created
  end

  def update
    alert = current_user.job_alerts.find(params[:id])
    alert.update!(alert_params)
    render json: { alert: }
  end

  def destroy
    current_user.job_alerts.find(params[:id]).destroy!
    render json: { ok: true }
  end
  private

  def alert_params
    permitted = params.permit(:name, :query, :location, :opportunityKind, :functionArea, :remoteOnly, :frequency, :active).to_h.transform_keys { _1.underscore }
    if permitted.key?("frequency") && !%w[daily weekly saved].include?(permitted["frequency"])
      raise ActionController::BadRequest, "Frequency must be daily, weekly, or saved"
    end
    permitted
  end
end
