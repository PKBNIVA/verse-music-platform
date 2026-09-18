class EmailDelivery
  def self.call(to:, template:, data:)
    return { delivered: false, reason: "Recipient unavailable" } if to.blank?
    webhook = ENV["EMAIL_DELIVERY_WEBHOOK"]
    return { delivered: false, reason: "EMAIL_DELIVERY_WEBHOOK not configured" } if webhook.blank?
    response = Faraday.post(webhook) do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Authorization"] = "Bearer #{ENV['EMAIL_DELIVERY_TOKEN']}" if ENV["EMAIL_DELIVERY_TOKEN"].present?
      request.body = { to:, template:, data: }.to_json
    end
    { delivered: response.success?, status: response.status }
  rescue StandardError => error
    Rails.logger.error("email delivery failed: #{error.class}")
    { delivered: false, reason: "delivery error" }
  end
end
