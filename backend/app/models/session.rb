# A signed-in browser. Only a SHA-256 digest of the bearer token is stored.
#
# Expiry slides: each use pushes expires_at out by the idle timeout, never past
# absolute_expires_at. Admin sessions are shorter on both counts. A stolen token
# therefore stops working soon after the victim stops using the app, and never
# outlives the hard cap.
#
# client_fingerprint is a coarse digest of the creating browser's User-Agent with
# version numbers removed (so browser updates do not change it). A token replayed
# from a different browser family is detected: an admin session is revoked on the
# spot; any other session is flagged once in the audit log and keeps working, so
# an ordinary user is never signed out by a false positive.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 7.days
  LIFETIME = 30.days
  ADMIN_IDLE_TIMEOUT = 12.hours
  ADMIN_LIFETIME = 7.days
  # Activity is written at most this often per session, so reads stay cheap.
  RENEW_AFTER = 5.minutes

  belongs_to :user
  scope :active, -> { where("expires_at > ?", Time.current) }
  # A signed-out session also closes its real-time sockets.
  after_destroy_commit { Realtime.disconnect(self) }

  # Deletes the sessions of `relation` and closes their open real-time sockets. Returns the count.
  def self.revoke!(relation)
    sessions = relation.includes(:user).to_a
    count = relation.delete_all
    Realtime.disconnect(sessions)
    count
  end

  def self.start!(user, token_digest:, user_agent:, now: Time.current)
    absolute = now + lifetime_for(user)
    user.sessions.create!(token_digest:, last_seen_at: now, absolute_expires_at: absolute,
      expires_at: [now + idle_timeout_for(user), absolute].min, client_fingerprint: fingerprint(user_agent))
  end

  def self.idle_timeout_for(user) = user.admin? ? ADMIN_IDLE_TIMEOUT : IDLE_TIMEOUT
  def self.lifetime_for(user) = user.admin? ? ADMIN_LIFETIME : LIFETIME

  # Browser and OS family only: "Chrome/129.0.6668.58" and "Chrome/130.0.1" match.
  def self.fingerprint(user_agent)
    family = user_agent.to_s.downcase.gsub(/[\d._]+/, "").squish
    Digest::SHA256.hexdigest("musilynk-session-client:#{family}")
  end

  def fingerprint_matches?(user_agent)
    client_fingerprint.blank? || client_fingerprint == self.class.fingerprint(user_agent)
  end

  # Slides expiry forward and adopts a fingerprint for sessions that predate one.
  # Sessions issued before sliding expiry existed (no absolute_expires_at) keep
  # the fixed expiry they were issued with (at most 30 days), except that an admin
  # session, which was issued without the second sign-in step, is cut to the admin
  # lifetime.
  def record_activity!(user_agent, now: Time.current)
    updates = {}
    updates[:client_fingerprint] = self.class.fingerprint(user_agent) if client_fingerprint.blank?
    if absolute_expires_at.nil?
      admin_cap = created_at + ADMIN_LIFETIME
      updates[:expires_at] = admin_cap if user.admin? && expires_at > admin_cap
    elsif last_seen_at.nil? || last_seen_at <= now - RENEW_AFTER
      updates[:last_seen_at] = now
      updates[:expires_at] = [now + self.class.idle_timeout_for(user), absolute_expires_at].min
    end
    update_columns(updates) if updates.any?
  end
end
