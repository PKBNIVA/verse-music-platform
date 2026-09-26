# A single-use, six-digit email sign-in code. Only an HMAC of the code is stored,
# keyed by a secret derived from secret_key_base and bound to the row id (a
# per-code salt), so a database leak does not reveal codes and a digest cannot be
# precomputed for all 10^6 codes at once.
class SignInCode < ApplicationRecord
  LIFETIME = 10.minutes
  MAX_ATTEMPTS = 5
  SIGN_UP_ROLES = %w[jobseeker employer].freeze

  validates :email, presence: true
  validates :pending_role, inclusion: { in: SIGN_UP_ROLES }, allow_nil: true
  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current).where("attempts < ?", MAX_ATTEMPTS) }

  # Invalidates older unused codes for the address and returns [record, raw_code].
  def self.issue!(email:, pending_name: nil, pending_role: nil)
    raw = format("%06d", SecureRandom.random_number(1_000_000))
    record = transaction do
      where(email:, used_at: nil).update_all(used_at: Time.current, updated_at: Time.current)
      code = new(id: "sign_#{SecureRandom.uuid}", email:, pending_name:, pending_role:, expires_at: LIFETIME.from_now)
      code.code_digest = code.digest_for(raw)
      code.save!
      code
    end
    [record, raw]
  end

  def self.latest_usable_for(email)
    usable.where(email: email.to_s.strip.downcase).order(created_at: :desc).first
  end

  def self.hmac_key
    Rails.application.key_generator.generate_key("sign-in-code-digest", 32)
  end

  def digest_for(raw)
    OpenSSL::HMAC.hexdigest("SHA256", self.class.hmac_key, "#{id}:#{raw}")
  end

  # Constant-time comparison; the caller locks the row and counts the attempt.
  def matches?(raw)
    candidate = raw.to_s.gsub(/\s+/, "")
    candidate = "" unless candidate.match?(/\A\d{6}\z/)
    ActiveSupport::SecurityUtils.secure_compare(code_digest, digest_for(candidate))
  end

  def sign_up? = pending_role.present?
end
