require "test_helper"
require "minitest/mock"
require_relative "../support/sentry_test_support"

class ErrorAlertingTest < ActionDispatch::IntegrationTest
  include SentryTestSupport

  setup do
    @admin = create_user("Alert Admin", "alert-admin@example.com", "admin")
    @artist = create_user("Alert Artist", "alert-artist@example.com", "jobseeker")
    @admin_token = session_for(@admin)
  end

  test "the Sentry test endpoint is admin-only" do
    post "/api/admin/health/sentry-test"
    assert_response :unauthorized
    post "/api/admin/health/sentry-test", headers: auth(session_for(@artist))
    assert_response :forbidden
    assert_equal 0, AuditLog.where(action: "admin.sentry_test").count
  end

  test "without a DSN the test endpoint answers captured false and is audited" do
    post "/api/admin/health/sentry-test", headers: auth(@admin_token)
    assert_response :success
    assert_equal false, response.parsed_body["captured"]
    assert_nil response.parsed_body["eventId"]
    log = AuditLog.find_by!(action: "admin.sentry_test")
    assert_equal @admin.id, log.actor_id
    assert_equal({ "captured" => false }, log.metadata)
  end

  test "with a DSN the test endpoint sends a tagged event with id and role only" do
    with_sentry do
      post "/api/admin/health/sentry-test", headers: auth(@admin_token)
      assert_response :success
      assert_equal true, response.parsed_body["captured"]
      assert response.parsed_body["eventId"].present?

      payload = sentry_payloads.last
      assert_equal "Admin::HealthController::SentryTestError", payload.dig("exception", "values", 0, "type")
      assert_equal "true", payload.dig("tags", "verse_test")
      assert_equal({ "id" => @admin.id, "role" => "admin" }, payload["user"])
      assert_no_match(/alert-admin@example\.com|#{Regexp.escape(@admin_token)}/, payload.to_json)
      assert_equal({ "captured" => true }, AuditLog.find_by!(action: "admin.sentry_test").metadata)
    end
  end

  test "an unexpected exception that becomes a 500 is reported without the bearer token" do
    with_sentry do
      ReadinessChecks.stub(:new, -> { raise "readiness exploded for alert-admin@example.com" }) do
        get "/api/readiness?token=query-secret", headers: auth(@admin_token)
      rescue RuntimeError
        # Test environments may re-raise instead of rendering the 500.
      end

      payload = sentry_payloads.last
      assert payload, "expected the 500 to be reported"
      assert_equal "RuntimeError", payload.dig("exception", "values", 0, "type")
      serialized = payload.to_json
      assert_no_match(/#{Regexp.escape(@admin_token)}|alert-admin@example\.com|query-secret/, serialized)
    end
  end

  test "a rescued error that still renders 5xx is reported; expected 4xx answers are not" do
    reconciler = Object.new
    def reconciler.call(_attempt) = raise(RazorpayGateway::GatewayError.new("provider timed out", code: "timeout"))
    missing = Object.new
    def missing.call(_attempt) = raise(BillingAttemptReconciler::ProviderResourceMissing, "gone")

    with_sentry do
      RazorpayConfig.stub(:usable?, true) do
        BillingAttempt.stub(:find, Object.new) do
          BillingAttemptReconciler.stub(:new, ->(*) { missing }) { post "/api/admin/billing-attempts/1/reconcile", headers: auth(@admin_token) }
          assert_response :not_found
          assert_empty sentry_events

          BillingAttemptReconciler.stub(:new, ->(*) { reconciler }) { post "/api/admin/billing-attempts/1/reconcile", headers: auth(@admin_token) }
          assert_response :bad_gateway
        end
      end

      assert_equal 1, sentry_events.size
      payload = sentry_payloads.first
      assert_equal "RazorpayGateway::GatewayError", payload.dig("exception", "values", 0, "type")
      assert_equal "handled_5xx", payload.dig("tags", "source")
      assert_equal "502", payload.dig("tags", "status")
    end
  end

  test "ordinary 4xx responses are never reported" do
    with_sentry do
      get "/api/jobs/00000000-0000-0000-0000-000000000000"
      post "/api/auth/login", params: { email: "nobody@example.com", password: "wrong" }, as: :json
      get "/api/me"
      assert_empty sentry_events
    end
  end

  test "a swallowed email enqueue failure is reported and the response is unchanged" do
    with_sentry do
      EmailDelivery.stub(:configured?, true) do
        EmailDeliveryJob.stub(:enqueue_code, ->(**) { raise Redis::CannotConnectError, "queue down" }) do
          post "/api/auth/otp/request", params: { email: @artist.email }, as: :json
        end
      end
      assert_response :success
      assert response.parsed_body["ok"]
      payload = sentry_payloads.last
      assert_equal "email_enqueue_failed", payload.dig("tags", "source")
      assert_no_match(/alert-artist@example\.com/, payload.to_json)
    end
  end

  private

  def create_user(name, email, role)
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active").tap(&:create_profile!)
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
