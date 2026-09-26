class NotificationsController < ApplicationController
  before_action -> { authenticate! }

  def index
    scope = current_user.notifications
    notifications = scope.order(created_at: :desc).limit(100).as_json.map do |row|
      row.transform_keys { _1.camelize(:lower) }.merge(type: row.delete("kind"))
    end
    render json: { notifications:, unread: scope.where(read_at: nil).count }
  end

  # Polled by the navigation (about every 30 s while the tab is visible).
  def unread
    render json: { unread: current_user.notifications.where(read_at: nil).count, unreadMessages: unread_messages }
  end

  def update
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: params[:read] == false ? nil : Time.current)
    render json: { ok: true }
  end

  def read_all
    now = Time.current
    updated = current_user.notifications.where(read_at: nil).update_all(read_at: now, updated_at: now)
    render json: { ok: true, updated: }
  end

  private

  def unread_messages
    Message.joins(:conversation)
      .where("conversations.candidate_id = :id OR conversations.employer_id = :id", id: current_user.id)
      .where(read_at: nil).where.not(sender_id: current_user.id).count
  end
end
