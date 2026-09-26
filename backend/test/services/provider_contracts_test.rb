require "test_helper"
require "minitest/mock"

class ProviderContractsTest < ActiveSupport::TestCase
  Response = Struct.new(:status, :body) do
    def success? = status.between?(200, 299)
  end

  test "Brevo receives the intended recipient and reset link without leaking its key into the body" do
    with_env("BREVO_API_KEY" => "test-api-key", "BREVO_SENDER_EMAIL" => "sender@example.invalid", "BREVO_SENDER_NAME" => "Verse") do
      transport = lambda do |url, &configure|
        assert_equal "https://api.brevo.com/v3/smtp/email", url
        request = fake_request
        configure.call(request)
        assert_equal "test-api-key", request.headers.fetch("api-key")
        message = JSON.parse(request.body)
        assert_equal [{ "email" => "recipient@example.invalid" }], message.fetch("to")
        assert_equal "sender@example.invalid", message.dig("sender", "email")
        assert_includes message.fetch("textContent"), "https://verse.example/reset-password?token=test"
        assert_not_includes request.body, "test-api-key"
        Response.new(201, "{}")
      end

      Faraday.stub(:post, transport) do
        result = EmailDelivery.call(to: "recipient@example.invalid", template: "reset_password",
          data: { link: "https://verse.example/reset-password?token=test" })
        assert_equal({ delivered: true, status: 201, provider: "brevo" }, result)
      end
    end
  end

  test "Brevo rejection is reported as unsuccessful delivery" do
    with_env("BREVO_API_KEY" => "test-api-key", "BREVO_SENDER_EMAIL" => "sender@example.invalid") do
      Faraday.stub(:post, response_transport(403)) do
        result = EmailDelivery.call(to: "recipient@example.invalid", template: "verify_email",
          data: { link: "https://verse.example/verify-email?token=test" })
        assert_equal false, result.fetch(:delivered)
        assert_equal 403, result.fetch(:status)
      end
    end
  end

  test "Razorpay order sends integer paise with server-side Basic authentication" do
    with_env("RAZORPAY_KEY_ID" => "rzp_test_id", "RAZORPAY_KEY_SECRET" => "test-secret") do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("https://api.razorpay.com/v1/orders") do |env|
          assert_equal "rzp_test_id:test-secret", Base64.decode64(env.request_headers.fetch("Authorization").delete_prefix("Basic "))
          assert_equal({ "amount" => 12_345, "currency" => "INR", "receipt" => "qa-order", "notes" => {} }, JSON.parse(env.request_body))
          assert_equal 12, env.request.timeout
          [200, { "Content-Type" => "application/json" }, '{"id":"order_test"}']
        end
      end

      assert_equal "order_test", razorpay(stubs).create_order(amount_paise: 12_345, currency: "INR", receipt: "qa-order").fetch("id")
      stubs.verify_stubbed_calls
    end
  end

  test "Razorpay server error is ambiguous so callers must reconcile before retrying" do
    with_env("RAZORPAY_KEY_ID" => "rzp_test_id", "RAZORPAY_KEY_SECRET" => "test-secret") do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("https://api.razorpay.com/v1/subscriptions") { [503, {}, '{"error":{"description":"Unavailable","code":"SERVER_ERROR"}}'] }
      end
      error = assert_raises(RazorpayGateway::GatewayError) do
        razorpay(stubs).create_subscription(plan_id: "plan_test")
      end
      assert error.ambiguous?
      assert_equal 503, error.http_status
      assert_equal "SERVER_ERROR", error.code
    end
  end

  test "Razorpay lookups for lost create responses send list filters as query parameters" do
    with_env("RAZORPAY_KEY_ID" => "rzp_test_id", "RAZORPAY_KEY_SECRET" => "test-secret") do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("https://api.razorpay.com/v1/orders?receipt=dep_abc") { [200, {}, '{"entity":"collection","count":0,"items":[]}'] }
        stub.get("https://api.razorpay.com/v1/subscriptions?count=100&from=100&skip=0&to=200") { [200, {}, '{"entity":"collection","count":0,"items":[]}'] }
      end
      gateway = razorpay(stubs)
      assert_equal [], gateway.orders_by_receipt("dep_abc")["items"]
      assert_equal [], gateway.subscriptions(from: Time.at(100), to: Time.at(200))["items"]
      stubs.verify_stubbed_calls
    end
  end

  private

  def razorpay(stubs) = RazorpayGateway.new(connection: Faraday.new { _1.adapter(:test, stubs) })

  def fake_request
    Struct.new(:headers, :body, :options).new({}, nil, Struct.new(:open_timeout, :timeout).new)
  end

  def response_transport(status, body = "{}")
    lambda do |_url, &configure|
      configure.call(fake_request)
      Response.new(status, body)
    end
  end

  def with_env(values)
    old = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
