# Sends transactional (token link) emails outside the request thread.
#
# The link carries a raw single-use token, so it is encrypted before it is
# written to the job table (GoodJob preserves job records and shows their
# arguments in its dashboard). The recipient is looked up by user id at
# delivery time so the job row holds no email address.
class EmailDeliveryJob < ApplicationJob
  # Raised for provider 5xx responses so they are retried like network errors.
  class ProviderUnavailable < StandardError; end

  LINK_PURPOSE = :email_delivery_link

  queue_as :mailers

  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError, ProviderUnavailable,
    wait: :polynomially_longer, attempts: 5

  def self.enqueue(user:, template:, link:)
    perform_later(user.id, template, seal(link))
  end

  def self.seal(link) = encryptor.encrypt_and_sign(link, purpose: LINK_PURPOSE, expires_in: 1.day)

  def self.unseal(sealed) = encryptor.decrypt_and_verify(sealed, purpose: LINK_PURPOSE)

  def self.encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("email-delivery-job-link", 32))
  end

  def perform(user_id, template, sealed_link)
    user = User.find_by(id: user_id)
    return log_skip("recipient_missing", template) unless user

    link = self.class.unseal(sealed_link)
    return log_skip("link_unreadable", template) unless link

    result = EmailDelivery.call(to: user.email, template:, data: { link: }, raise_errors: true)
    raise ProviderUnavailable, "email provider returned #{result[:status]}" if result[:status].to_i >= 500

    log_skip(result[:reason] || "rejected_#{result[:status]}", template) unless result[:delivered]
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    log_skip("link_unreadable", template)
  end

  private

  def log_skip(reason, template)
    Rails.logger.warn({ event: "email_delivery_skipped", jobId: job_id, template:, reason: }.to_json)
  end
end
