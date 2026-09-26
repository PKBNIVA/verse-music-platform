class NotificationsController < ApplicationController
  before_action -> { authenticate! }, except: :unsubscribe

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

  def preferences
    render json: { emailNotifications: NotificationEmail.opted_in?(current_user) }
  end

  def update_preferences
    value = params[:emailNotifications]
    return render_error("emailNotifications must be true or false.", :bad_request, "INVALID_PREFERENCE") unless [true, false].include?(value)

    profile = current_user.profile || current_user.create_profile!
    profile.update!(email_notifications: value)
    render json: { emailNotifications: profile.email_notifications }
  end

  # One-click unsubscribe from a notification email: no sign-in, the signed token names the
  # user. GET (link) and POST (RFC 8058 List-Unsubscribe-Post) both turn emails off.
  def unsubscribe
    user = NotificationEmail.user_for_unsubscribe_token(params[:token])
    return render_error("This unsubscribe link is invalid.", :bad_request, "INVALID_TOKEN") unless user

    (user.profile || user.create_profile!).update!(email_notifications: false)
    Rails.logger.info({ event: "notification_email_unsubscribed", userId: user.id }.to_json)
    render json: { ok: true, emailNotifications: false }
  end

  private

  def unread_messages
    Message.joins(:conversation)
      .where("conversations.candidate_id = :id OR conversations.employer_id = :id", id: current_user.id)
      .where(read_at: nil).where.not(sender_id: current_user.id).count
  end
end
