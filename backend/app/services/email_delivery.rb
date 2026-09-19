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
    }
  }.freeze

  def self.call(to:, template:, data:)
    return { delivered: false, reason: "Recipient unavailable" } if to.blank?
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
    { delivered: response.success?, status: response.status }
  rescue StandardError => error
    Rails.logger.error("email delivery failed: #{error.class}")
    { delivered: false, reason: "delivery error" }
  end

  def self.deliver_with_resend(to:, template:, data:)
    content = TEMPLATES.fetch(template) { raise ArgumentError, "Unknown email template" }
    link = data.fetch(:link)
    response = Faraday.post("https://api.resend.com/emails") do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Authorization"] = "Bearer #{ENV.fetch('RESEND_API_KEY')}"
      request.body = {
        from: ENV.fetch("EMAIL_FROM"), to: [to], subject: content[:subject],
        html: email_html(content:, link:),
        text: "#{content[:heading]}\n\n#{content[:copy]}\n\n#{link}"
      }.to_json
      request.options.open_timeout = 5
      request.options.timeout = 10
    end
    { delivered: response.success?, status: response.status }
  end

  def self.email_html(content:, link:)
    safe_link = ERB::Util.html_escape(link)
    <<~HTML.squish
      <!doctype html><html><body style="margin:0;background:#0b0b12;color:#f8fafc;font-family:Arial,sans-serif"><div style="max-width:560px;margin:0 auto;padding:40px 24px"><div style="font-size:22px;font-weight:800;color:#a78bfa">VERSE</div><h1 style="font-size:28px;margin:28px 0 12px">#{content[:heading]}</h1><p style="color:#cbd5e1;line-height:1.6">#{content[:copy]}</p><a href="#{safe_link}" style="display:inline-block;margin-top:18px;padding:13px 20px;border-radius:12px;background:#7c3aed;color:white;text-decoration:none;font-weight:700">#{content[:action]}</a><p style="margin-top:28px;color:#94a3b8;font-size:13px">If you did not request this, you can safely ignore this email.</p></div></body></html>
    HTML
  end

  private_class_method :deliver_with_resend, :email_html
end
