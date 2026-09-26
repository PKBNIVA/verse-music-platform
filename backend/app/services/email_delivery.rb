class EmailDelivery
  TEMPLATES = {
    "reset_password" => {
      subject: "Reset your Verse password",
      heading: "Reset your password",
      copy: "Use the secure link below to choose a new password. The link expires in two hours.",
      action: "Reset password"
    },
    "verify_email" => {
      subject: "Verify your Verse email",
      heading: "Verify your email",
      copy: "Confirm this email address to secure your Verse account.",
      action: "Verify email"
    },
    # data: { code: }. Deliberately no link: a code-only email cannot be used
    # by link scanners or from a forwarded message preview.
    "sign_in_code" => {
      subject: "Your Verse sign-in code",
      heading: "Your sign-in code",
      copy: "Enter this code on Verse to continue. It expires in 10 minutes and can be used once. Verse will never ask you for this code by phone or chat.",
      action: nil
    }
  }.freeze

  # Returns a result hash. Network and configuration errors are reported as an
  # unsuccessful delivery unless raise_errors is true (used by EmailDeliveryJob
  # so it can retry transient failures).
  def self.call(to:, template:, data:, raise_errors: false)
    return { delivered: false, reason: "Recipient unavailable" } if to.blank?
    return deliver_with_brevo(to:, template:, data:) if brevo_configured?
    return deliver_with_resend(to:, template:, data:) if ENV["RESEND_API_KEY"].present?

    webhook = ENV["EMAIL_DELIVERY_WEBHOOK"]
    return { delivered: false, reason: "Email provider not configured" } if webhook.blank?
    response = Faraday.post(webhook) do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Authorization"] = "Bearer #{ENV['EMAIL_DELIVERY_TOKEN']}" if ENV["EMAIL_DELIVERY_TOKEN"].present?
      request.body = { to:, template:, data: }.to_json
      request.options.open_timeout = 5
      request.options.timeout = 10
    end
    log_rejection("webhook", template, response)
    { delivered: response.success?, status: response.status }
  rescue StandardError => error
    raise if raise_errors
    Rails.logger.error("email delivery failed: #{error.class}")
    { delivered: false, reason: "delivery error" }
  end

  def self.provider
    return "brevo" if brevo_configured?
    return "resend" if ENV["RESEND_API_KEY"].present?
    "webhook" if ENV["EMAIL_DELIVERY_WEBHOOK"].present?
  end

  def self.configured? = provider.present?

  def self.brevo_configured?
    ENV["BREVO_API_KEY"].present? && ENV["BREVO_SENDER_EMAIL"].present?
  end

  def self.deliver_with_brevo(to:, template:, data:)
    content = TEMPLATES.fetch(template) { raise ArgumentError, "Unknown email template" }
    response = Faraday.post("https://api.brevo.com/v3/smtp/email") do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Accept"] = "application/json"
      request.headers["api-key"] = ENV.fetch("BREVO_API_KEY")
      request.body = {
        sender: { name: ENV.fetch("BREVO_SENDER_NAME", "Verse"), email: ENV.fetch("BREVO_SENDER_EMAIL") },
        to: [{ email: to }], subject: content[:subject],
        htmlContent: email_html(content:, data:),
        textContent: email_text(content:, data:)
      }.to_json
      request.options.open_timeout = 5
      request.options.timeout = 10
    end
    log_rejection("brevo", template, response)
    { delivered: response.success?, status: response.status, provider: "brevo" }
  end

  def self.deliver_with_resend(to:, template:, data:)
    content = TEMPLATES.fetch(template) { raise ArgumentError, "Unknown email template" }
    response = Faraday.post("https://api.resend.com/emails") do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Authorization"] = "Bearer #{ENV.fetch('RESEND_API_KEY')}"
      request.body = {
        from: ENV.fetch("EMAIL_FROM"), to: [to], subject: content[:subject],
        html: email_html(content:, data:),
        text: email_text(content:, data:)
      }.to_json
      request.options.open_timeout = 5
      request.options.timeout = 10
    end
    log_rejection("resend", template, response)
    { delivered: response.success?, status: response.status }
  end

  # Logs only the provider, template and status code: provider response bodies
  # can echo the message (and therefore the token link or code) back.
  def self.log_rejection(provider, template, response)
    return if response.success?
    Rails.logger.warn({ event: "email_delivery_rejected", provider:, template:, status: response.status }.to_json)
  end

  # Link templates require data[:link]; code templates require data[:code].
  def self.email_body_value(content:, data:)
    content[:action] ? data.fetch(:link) : data.fetch(:code).to_s
  end

  def self.email_text(content:, data:)
    "#{content[:heading]}\n\n#{content[:copy]}\n\n#{email_body_value(content:, data:)}"
  end

  def self.email_html(content:, data:)
    value = ERB::Util.html_escape(email_body_value(content:, data:))
    body = if content[:action]
      %(<a href="#{value}" style="display:inline-block;margin-top:18px;padding:13px 20px;border-radius:12px;background:#7c3aed;color:white;text-decoration:none;font-weight:700">#{content[:action]}</a>)
    else
      %(<p style="margin:22px 0 0;font-family:'Courier New',monospace;font-size:34px;font-weight:800;letter-spacing:8px;color:#f8fafc">#{value}</p>)
    end
    <<~HTML.squish
      <!doctype html><html><body style="margin:0;background:#0b0b12;color:#f8fafc;font-family:Arial,sans-serif"><div style="max-width:560px;margin:0 auto;padding:40px 24px"><div style="font-size:22px;font-weight:800;color:#a78bfa">VERSE</div><h1 style="font-size:28px;margin:28px 0 12px">#{content[:heading]}</h1><p style="color:#cbd5e1;line-height:1.6">#{content[:copy]}</p>#{body}<p style="margin-top:28px;color:#94a3b8;font-size:13px">If you did not request this, you can safely ignore this email.</p></div></body></html>
    HTML
  end

  private_class_method :deliver_with_brevo, :deliver_with_resend, :email_html, :email_text, :email_body_value, :log_rejection

  # --- Notification emails (messaging/notifications area) -----------------------
  # Sends content already rendered by NotificationEmail through the configured
  # provider. Same result/raise_errors contract as .call; logs never include content.
  def self.deliver_rendered(to:, template:, subject:, html:, text:, raise_errors: false)
    return { delivered: false, reason: "Recipient unavailable" } if to.blank?

    provider_name = provider
    return { delivered: false, reason: "Email provider not configured" } unless provider_name

    response = Faraday.post(rendered_endpoint(provider_name)) do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Accept"] = "application/json"
      case provider_name
      when "brevo"
        request.headers["api-key"] = ENV.fetch("BREVO_API_KEY")
        request.body = { sender: { name: ENV.fetch("BREVO_SENDER_NAME", "Verse"), email: ENV.fetch("BREVO_SENDER_EMAIL") },
          to: [{ email: to }], subject:, htmlContent: html, textContent: text }.to_json
      when "resend"
        request.headers["Authorization"] = "Bearer #{ENV.fetch('RESEND_API_KEY')}"
        request.body = { from: ENV.fetch("EMAIL_FROM"), to: [to], subject:, html:, text: }.to_json
      else
        request.headers["Authorization"] = "Bearer #{ENV['EMAIL_DELIVERY_TOKEN']}" if ENV["EMAIL_DELIVERY_TOKEN"].present?
        request.body = { to:, template:, data: { subject:, html:, text: } }.to_json
      end
      request.options.open_timeout = 5
      request.options.timeout = 10
    end
    log_rejection(provider_name, template, response)
    { delivered: response.success?, status: response.status, provider: provider_name }
  rescue StandardError => error
    raise if raise_errors
    Rails.logger.error("notification email delivery failed: #{error.class}")
    { delivered: false, reason: "delivery error" }
  end

  def self.rendered_endpoint(provider_name)
    { "brevo" => "https://api.brevo.com/v3/smtp/email", "resend" => "https://api.resend.com/emails" }
      .fetch(provider_name) { ENV.fetch("EMAIL_DELIVERY_WEBHOOK") }
  end
  private_class_method :rendered_endpoint
end
