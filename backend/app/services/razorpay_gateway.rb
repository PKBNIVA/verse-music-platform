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

  def subscription(subscription_id)
    request(:get, "subscriptions/#{subscription_id}")
  end

  def order(order_id)
    request(:get, "orders/#{order_id}")
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
      request.options.open_timeout = 3
      request.options.timeout = 12
    end
    body = JSON.parse(response.body.presence || "{}")
    return body if response.success?

    message = body.dig("error", "description") || "Razorpay request failed (HTTP #{response.status})"
    code = body.dig("error", "code") || "http_#{response.status}"
    ambiguous = method == :post && (response.status >= 500 || [408, 429].include?(response.status))
    raise GatewayError.new(message, code:, http_status: response.status, ambiguous:)
  rescue Faraday::TimeoutError => error
    raise GatewayError.new("Razorpay request timed out", code: "timeout", ambiguous: method == :post), cause: error
  rescue Faraday::ConnectionFailed => error
    raise GatewayError.new("Razorpay connection failed", code: "connection_failed", ambiguous: method == :post), cause: error
  rescue Faraday::Error => error
    raise GatewayError.new("Razorpay transport failed", code: "transport_error", ambiguous: method == :post), cause: error
  rescue JSON::ParserError => error
    raise GatewayError.new("Razorpay returned an invalid response", code: "invalid_response", ambiguous: method == :post), cause: error
  end

  class GatewayError < StandardError
    attr_reader :code, :http_status

    def initialize(message, code: "gateway_error", http_status: nil, ambiguous: false)
      super(message)
      @code = code
      @http_status = http_status
      @ambiguous = ambiguous
    end

    def ambiguous? = @ambiguous
  end
end
