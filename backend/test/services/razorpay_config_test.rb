require "test_helper"
require "minitest/mock"

class RazorpayConfigTest < ActiveSupport::TestCase
  KEYS = %w[RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET RAZORPAY_WEBHOOK_SECRET RAZORPAY_ALLOW_TEST_MODE RAZORPAY_ALLOW_LIVE_MODE].freeze

  setup { @previous = KEYS.to_h { [_1, ENV[_1]] } }
  teardown { @previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value } }

  test "production refuses test keys unless test mode is explicitly allowed" do
    in_production do
      set_keys("rzp_test_abc")
      assert_equal "test", RazorpayConfig.mode
      assert_not RazorpayConfig.usable?
      assert_raises(RazorpayGateway::GatewayError) { RazorpayGateway.new }

      ENV["RAZORPAY_ALLOW_TEST_MODE"] = "true"
      assert RazorpayConfig.usable?
    end
  end

  test "production accepts live keys and fails closed on unrecognised keys" do
    in_production do
      set_keys("rzp_live_abc")
      assert RazorpayConfig.usable?
      set_keys("key_without_prefix")
      assert_not RazorpayConfig.usable?
    end
  end

  test "non-production refuses live keys unless live mode is explicitly allowed" do
    set_keys("rzp_live_abc")
    assert_equal "live", RazorpayConfig.mode
    assert_not RazorpayConfig.usable?

    ENV["RAZORPAY_ALLOW_LIVE_MODE"] = "true"
    assert RazorpayConfig.usable?

    set_keys("rzp_test_abc")
    assert RazorpayConfig.usable?
  end

  test "missing keys are not usable" do
    ENV.delete("RAZORPAY_KEY_ID")
    assert_equal "disabled", RazorpayConfig.mode
    assert_not RazorpayConfig.usable?
  end

  test "admin readiness reports the key mode and marks a refused key as not ready" do
    set_keys("rzp_live_abc")
    payments = ReadinessChecks.new.call.fetch(:payments)
    assert_equal "live", payments.fetch(:mode)
    assert_equal false, payments.fetch(:ok)

    set_keys("rzp_test_abc")
    assert_equal true, ReadinessChecks.new.call.dig(:payments, :ok)
  end

  test "production readiness fails payments for a test key without the override" do
    in_production do
      set_keys("rzp_test_abc")
      ENV["RAZORPAY_WEBHOOK_SECRET"] = "whsec"
      assert_equal false, ReadinessChecks.new.call.dig(:payments, :ok)
      ENV["RAZORPAY_ALLOW_TEST_MODE"] = "true"
      assert_equal true, ReadinessChecks.new.call.dig(:payments, :ok)
    end
  end

  private

  def set_keys(key_id)
    ENV["RAZORPAY_KEY_ID"] = key_id
    ENV["RAZORPAY_KEY_SECRET"] = "secret"
  end

  def in_production(&block)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production"), &block)
  end
end
