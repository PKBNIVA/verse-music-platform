# Delivers one notification email (see Notifier / NotificationEmail). The job row holds
# the recipient's id, the template name and display values only: no email address and
# no message body.
class NotificationEmailJob < ApplicationJob
  queue_as :mailers

  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError, EmailDeliveryJob::ProviderUnavailable,
    wait: :polynomially_longer, attempts: 5

  def perform(user_id, template, params = {})
    user = User.find_by(id: user_id)
    return log_skip("recipient_missing", template) unless user
    return log_skip("recipient_ineligible", template) unless NotificationEmail.deliverable_to?(user)

    content = NotificationEmail.render(template, params, user)
    result = EmailDelivery.deliver_rendered(to: user.email, template:, **content, raise_errors: true)
    raise EmailDeliveryJob::ProviderUnavailable, "email provider returned #{result[:status]}" if result[:status].to_i >= 500

    log_skip(result[:reason] || "rejected_#{result[:status]}", template) unless result[:delivered]
  rescue KeyError
    log_skip("unknown_template", template)
  end

  private

  def log_skip(reason, template)
    Rails.logger.warn({ event: "notification_email_skipped", jobId: job_id, template:, reason: }.to_json)
  end
end
