class NotificationsController < ApplicationController
  before_action -> { authenticate! }

  def index
    scope = current_user.notifications
    notifications = scope.order(created_at: :desc).limit(100).as_json.map do |row|
      row.transform_keys { _1.camelize(:lower) }.merge(type: row.delete("kind"))
    end
    render json: { notifications:, unread: scope.where(read_at: nil).count }
  end

  def unread
    render json: { unread: current_user.notifications.where(read_at: nil).count }
  end

  def update
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: params[:read] == false ? nil : Time.current)
    render json: { ok: true }
  end
end
