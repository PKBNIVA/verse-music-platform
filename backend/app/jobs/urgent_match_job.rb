# Ranks and alerts musicians for a freshly posted UrgentRequest (UrgentMatcher.notify!), off the request
# thread. Enqueued by UrgentRequestsController#create once the row is committed.
#
# Safe to run twice (retry, duplicate enqueue): the job claims the request with a conditional UPDATE on
# match_status, so only one run does the work, and UrgentMatcher itself records each
# (request, user, channel) once, so a retry after a partial run never re-alerts anyone. Push, email and
# WhatsApp deliveries are enqueued from here (Notifier / WhatsappAlertJob), never from the request.
# Logs ids only, never names, emails or request text.
class UrgentMatchJob < ApplicationJob
  queue_as JobQueues::URGENT

  # How long a "matching" claim is trusted before another run may take it over (a crashed worker).
  STALE_CLAIM = 10.minutes

  discard_on ActiveRecord::RecordNotFound
  retry_on ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::LockWaitTimeout,
    Net::OpenTimeout, Net::ReadTimeout, Faraday::ConnectionFailed, Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5

  def perform(urgent_request_id)
    item = UrgentRequest.find(urgent_request_id)
    return unless claim!(item)

    if item.reload.status == "open"
      UrgentMatcher.notify!(item)
      item.update_columns(match_status: "done", matched_at: Time.current)
    else
      item.update_columns(match_status: "skipped", matched_at: Time.current)
    end
    # update_columns skips the model's callbacks: tell the hirer's page directly.
    Realtime.urgent_request_changed(item)
  rescue StandardError
    # Hand the claim back so the retry (or a re-enqueue) can take it; already-sent alerts are not repeated.
    UrgentRequest.where(id: urgent_request_id, match_status: "matching").update_all(match_status: "pending") if item&.persisted?
    raise
  end

  private

  # True for exactly one caller: pending -> matching (or a stale "matching" left by a dead worker).
  def claim!(item)
    UrgentRequest.where(id: item.id)
      .where("match_status = 'pending' OR (match_status = 'matching' AND updated_at < ?)", STALE_CLAIM.ago)
      .update_all(match_status: "matching", updated_at: Time.current) == 1
  end
end
