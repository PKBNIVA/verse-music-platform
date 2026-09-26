class AvailabilityController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }
  def index = render(json: { windows: AvailabilityWindow.where(user: current_user).order(start_at: :asc).limit(200).as_json.map { _1.transform_keys { |key| key.camelize(:lower) } } })
  def create
    window = AvailabilityWindow.create!(user: current_user, start_at: params[:startAt], end_at: params[:endAt], status: params[:status] || "available", city: params[:city], note: params[:note])
    render json: { id: window.id }, status: :created
  end
  def destroy
    AvailabilityWindow.where(user: current_user).find(params[:id]).destroy!
    render json: { ok: true }
  end
end
