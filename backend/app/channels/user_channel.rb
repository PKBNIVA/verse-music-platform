# The signed-in user's own stream: a hint whenever their unread counts may have changed (a new
# notification, a new message to them). Payloads carry ids only; the app refetches the counts from
# GET /api/notifications/unread, so authorisation stays with the endpoints.
class UserChannel < ApplicationCable::Channel
  def subscribed = stream_for(current_user)
end
