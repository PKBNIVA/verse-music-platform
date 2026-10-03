# Broadcasts to the Action Cable channels from model callbacks and jobs. Payloads are ids, types
# and states only: the app refetches anything else from the API, so authorisation stays there.
# A failed broadcast is reported and swallowed: the write it follows has already committed, and
# polling (the fallback) picks the change up.
module Realtime
  module_function

  # Whether pages should open the socket (config/realtime.yml `enabled`; sign-in and GET /me say so).
  # Off means every page polls at its old pace and no ticket is ever requested.
  # CABLE_ENABLED (optional, "true"/"false") overrides config/realtime.yml without a deploy.
  def enabled?
    override = ENV["CABLE_ENABLED"].to_s.strip.downcase
    return override == "true" if override.present?
    RealtimeTicket.settings.fetch("enabled", true) == true
  end

  # Closes the open sockets of these sessions (call before deleting them). Revocation must not fail
  # because the adapter is down, so errors are reported and swallowed.
  def disconnect(sessions)
    Array(sessions).each do |session|
      ActionCable.server.remote_connections.where(current_user: session.user, current_session: session).disconnect(reconnect: false)
    end
  rescue StandardError => e
    ErrorReporter.capture(e, tags: { source: "realtime" })
  end

  def broadcast(channel, record, payload)
    channel.broadcast_to(record, payload)
  rescue StandardError => e
    ErrorReporter.capture(e, tags: { source: "realtime", channel: channel.name })
    Rails.logger.warn("[realtime] #{channel.name} broadcast failed: #{e.class}")
  end

  def message_created(message)
    conversation = message.conversation
    broadcast(ConversationChannel, conversation, { type: "message", id: message.id, conversationId: conversation.id })
    recipient = conversation.counterpart_for(message.sender)
    broadcast(UserChannel, recipient, { type: "message", conversationId: conversation.id }) if recipient
  end

  def notification_created(notification)
    broadcast(UserChannel, notification.user, { type: "notification", id: notification.id })
  end

  def urgent_request_changed(request, change = "status")
    broadcast(UrgentRequestChannel, request, { type: change, id: request.id, status: request.status, matchStatus: request.match_status })
  end
end
