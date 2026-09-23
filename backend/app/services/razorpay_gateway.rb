require "base64"

class RazorpayGateway
  API_URL = "https://api.razorpay.com/v1"

  def initialize
    @key_id = ENV.fetch("RAZORPAY_KEY_ID")
    @key_secret = ENV.fetch("RAZORPAY_KEY_SECRET")
  end

  def create_order(amount_paise:, currency:, receipt:, notes: {})
    post("orders", amount: amount_paise, currency:, receipt:, notes:)
  end

  def create_subscription(plan_id:, total_count: 100, start_at: nil, notes: {})
    payload = { plan_id:, total_count:, quantity: 1, customer_notify: 1, notes: }
    payload[:start_at] = start_at if start_at
    post("subscriptions", payload)
  end

  def cancel_subscription(subscription_id)
    post("subscriptions/#{subscription_id}/cancel", cancel_at_cycle_end: 1)
  end

  def payment(payment_id)
    request(:get, "payments/#{payment_id}")
  end

  private

  def post(path, payload)
    request(:post, path, payload)
  end

  def request(method, path, payload = nil)
    response = Faraday.public_send(method, "#{API_URL}/#{path}") do |request|
      request.headers["Content-Type"] = "application/json"
      request.headers["Authorization"] = "Basic #{Base64.strict_encode64("#{@key_id}:#{@key_secret}")}" 
      request.body = JSON.generate(payload) if payload
      request.options.timeout = 15
    end
    body = JSON.parse(response.body.presence || "{}")
    return body if response.success?

    message = body.dig("error", "description") || "Razorpay request failed (HTTP #{response.status})"
    raise GatewayError, message
  rescue Faraday::Error, JSON::ParserError => error
    raise GatewayError, "Razorpay is temporarily unavailable: #{error.message}"
  end

  class GatewayError < StandardError; end
end
