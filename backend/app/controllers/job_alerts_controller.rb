class JobAlertsController < ApplicationController
  before_action -> { authenticate!("jobseeker") }

  def index = render(json: { alerts: current_user.job_alerts.order(created_at: :desc) })

  def create
    alert = current_user.job_alerts.create!(params.permit(:name, :query, :location, :opportunityKind, :functionArea, :remoteOnly, :frequency).to_h.transform_keys { _1.underscore })
    render json: { id: alert.id }, status: :created
  end

  def destroy
    current_user.job_alerts.find(params[:id]).destroy!
    render json: { ok: true }
  end
end
