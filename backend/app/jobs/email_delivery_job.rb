# Sends transactional (token link or sign-in code) emails outside the request thread.
#
# The link or code is a single-use secret, so it is encrypted before it is
# written to the job table (GoodJob preserves job records and shows their
# arguments in its dashboard). The recipient is looked up by user id at
# delivery time so the job row holds no email address; a sign-up code, which
# has no user yet, carries its recipient address encrypted too.
#
# Arguments: (user_id, template, sealed_secret, sealed_email = nil). The first
# three keep the shape of jobs enqueued before sign-in codes existed.
class EmailDeliveryJob < ApplicationJob
  # Raised for provider 5xx responses so they are retried like network errors.
  class ProviderUnavailable < StandardError; end

  LINK_PURPOSE = :email_delivery_link
  RECIPIENT_PURPOSE = :email_delivery_recipient
  CODE_TEMPLATES = %w[sign_in_code].freeze

  queue_as :mailers

  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError, ProviderUnavailable,
    wait: :polynomially_longer, attempts: 5

  def self.enqueue(user:, template:, link:)
    perform_later(user.id, template, seal(link))
  end

  # Sends a sign-in code to an existing user (user:) or to a not-yet-created
  # account's address (email:). Codes expire quickly, so the seal does too.
  def self.enqueue_code(template:, code:, user: nil, email: nil)
    raise ArgumentError, "user or email required" if user.nil? && email.blank?
    sealed_email = user ? nil : seal(email, purpose: RECIPIENT_PURPOSE, expires_in: SignInCode::LIFETIME)
    perform_later(user&.id, template, seal(code, expires_in: SignInCode::LIFETIME), sealed_email)
  end

  def self.seal(value, purpose: LINK_PURPOSE, expires_in: 1.day) = encryptor.encrypt_and_sign(value, purpose:, expires_in:)

  def self.unseal(sealed, purpose: LINK_PURPOSE) = encryptor.decrypt_and_verify(sealed, purpose:)

  def self.encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("email-delivery-job-link", 32))
  end

  def perform(user_id, template, sealed_link, sealed_email = nil)
    to = recipient_for(user_id, sealed_email)
    return log_skip("recipient_missing", template) if to.blank?

    secret = self.class.unseal(sealed_link)
    return log_skip("link_unreadable", template) unless secret

    data = CODE_TEMPLATES.include?(template) ? { code: secret } : { link: secret }
    result = EmailDelivery.call(to:, template:, data:, raise_errors: true)
    raise ProviderUnavailable, "email provider returned #{result[:status]}" if result[:status].to_i >= 500

    log_skip(result[:reason] || "rejected_#{result[:status]}", template) unless result[:delivered]
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    log_skip("link_unreadable", template)
  end

  private

  def recipient_for(user_id, sealed_email)
    return User.find_by(id: user_id)&.email if user_id.present?
    self.class.unseal(sealed_email, purpose: RECIPIENT_PURPOSE) if sealed_email.present?
  end

  def log_skip(reason, template)
    Rails.logger.warn({ event: "email_delivery_skipped", jobId: job_id, template:, reason: }.to_json)
  end
end
