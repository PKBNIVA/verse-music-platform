# Daily housekeeping for authentication records: expired sessions and email
# tokens that expired or were used more than RETENTION ago.
class AuthCleanupJob < ApplicationJob
  RETENTION = 7.days
  BATCH_SIZE = 1_000

  queue_as :scheduled

  def perform(now = Time.current)
    cutoff = now - RETENTION
    sessions = delete_in_batches(Session.where(expires_at: ..now))
    tokens = delete_in_batches(EmailToken.where(expires_at: ...cutoff).or(EmailToken.where(used_at: ...cutoff)))
    Rails.logger.info({ event: "auth_cleanup", sessionsDeleted: sessions, emailTokensDeleted: tokens }.to_json)
  end

  private

  def delete_in_batches(scope)
    deleted = 0
    scope.in_batches(of: BATCH_SIZE) { |batch| deleted += batch.delete_all }
    deleted
  end
end
