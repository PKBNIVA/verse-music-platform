# Single source of truth for whether Razorpay may be used in this environment.
#
# Production must use live keys (`rzp_live_`) unless RAZORPAY_ALLOW_TEST_MODE=true;
# every other environment must use test keys unless RAZORPAY_ALLOW_LIVE_MODE=true.
# A key that fails this guard is treated exactly like a missing key (fail closed).
module RazorpayConfig
  module_function

  def key_id = ENV["RAZORPAY_KEY_ID"].to_s.strip
  def key_secret = ENV["RAZORPAY_KEY_SECRET"].to_s

  # Any key id was supplied, whether or not it is usable here.
  def key_present? = key_id.present?

  def mode(value = key_id)
    return "disabled" if value.blank?
    return "live" if value.start_with?("rzp_live_")
    return "test" if value.start_with?("rzp_test_")

    "unknown"
  end

  def key_mode_allowed?(value = key_id)
    case mode(value)
    when "disabled" then false
    when "live" then !Rails.env.production? ? ENV["RAZORPAY_ALLOW_LIVE_MODE"] == "true" : true
    when "test" then Rails.env.production? ? ENV["RAZORPAY_ALLOW_TEST_MODE"] == "true" : true
    else !Rails.env.production?
    end
  end

  # Keys are present and allowed for this environment.
  def usable? = key_present? && key_secret.present? && key_mode_allowed?

  # Local Razorpay simulator (RazorpaySimulator) instead of api.razorpay.com.
  # Never in production, and only with a test-mode key so live credentials can never reach it.
  def simulator? = !Rails.env.production? && ENV["RAZORPAY_SIMULATOR"] == "true" && mode == "test"

  # Safe to show to a signed-in user: whether payments run against Razorpay test mode
  # (or the simulator). Never exposes the key itself.
  def test_mode? = usable? && mode == "test"
end
