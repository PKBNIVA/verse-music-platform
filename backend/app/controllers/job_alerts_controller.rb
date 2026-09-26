class JobAlertsController < ApplicationController
  class InvalidAlert < StandardError; end

  before_action -> { authenticate!("jobseeker") }
  # Surface the reason to the client; a raised BadRequest rendered as a bare "Bad Request" in production.
  rescue_from InvalidAlert, with: ->(error) { render_error(error.message, :unprocessable_entity) }

  def index = render(json: { alerts: current_user.job_alerts.order(created_at: :desc) })

  def create
    alert = current_user.job_alerts.create!({ "frequency" => "saved" }.merge(alert_params))
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
      raise InvalidAlert, "Frequency must be daily, weekly, or saved"
    end
    # A blank name rendered as an empty heading on the alerts page.
    permitted["name"] = permitted["name"].to_s.strip.first(120).presence || "Saved search" if permitted.key?("name") || action_name == "create"
    permitted
  end
end
