class NotificationsController < ApplicationController
  before_action -> { authenticate! }

  def index
    render json: { notifications: current_user.notifications.order(created_at: :desc).limit(100).as_json.map { |row| row.transform_keys { _1.camelize(:lower) }.merge(type: row.delete("kind")) } }
  end

  def update
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: params[:read] == false ? nil : Time.current)
    render json: { ok: true }
  end
end
