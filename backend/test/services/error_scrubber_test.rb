require "test_helper"

class ErrorScrubberTest < ActiveSupport::TestCase
  test "strings lose email addresses, bearer tokens and secret query parameters" do
    raw = "user jane.doe+tag@example.co.uk sent Authorization: Bearer abc.DEF-123_xyz= to " \
      "https://verse.test/reset-password?token=s3cr3t&page=2&code=123456#frag and /x?reset_token=zz"
    clean = ErrorScrubber.scrub_string(raw)

    assert_no_match(/jane\.doe|example\.co\.uk|abc\.DEF|s3cr3t|123456|=zz/, clean)
    assert_includes clean, "[email]"
    assert_includes clean, "Bearer [Filtered]"
    assert_includes clean, "?token=[Filtered]&page=2&code=[Filtered]#frag"
    assert_includes clean, "?reset_token=[Filtered]"
  end

  test "nested hashes drop sensitive keys and scrub the remaining strings" do
    clean = ErrorScrubber.scrub(
      "password" => "hunter2", "passwordConfirmation" => "hunter2", "accessToken" => "tok", "otp" => "111111",
      "code" => "222222", "razorpay_signature" => "sig", "secret" => "s", "body" => "private message",
      "Authorization" => "Bearer x", "HTTP_COOKIE" => "a=b", "email" => "a@b.io",
      "nested" => [{ "note" => "mail me at z@y.dev", "status" => 500 }], "template" => "verify_email"
    )

    %w[password passwordConfirmation accessToken otp code razorpay_signature secret body Authorization HTTP_COOKIE email].each do |key|
      assert_equal "[Filtered]", clean[key], key
    end
    assert_equal({ "note" => "mail me at [email]", "status" => 500 }, clean["nested"].first)
    assert_equal "verify_email", clean["template"]
  end

  test "URL-encoded email addresses are scrubbed too" do
    assert_equal "/lookup?q=[email]&x=1", ErrorScrubber.scrub_string("/lookup?q=Jane.Doe%40Example.com&x=1")
  end

  test "query strings are scrubbed without a leading question mark" do
    assert_equal "token=[Filtered]&page=1", ErrorScrubber.scrub_query("token=abc&page=1")
    assert_equal "", ErrorScrubber.scrub_query("")
  end

  test "users are reduced to id and role" do
    assert_equal({ id: 7, role: "admin" }, ErrorScrubber.scrub_user("id" => 7, "role" => "admin", "email" => "a@b.io", "ip_address" => "1.2.3.4"))
    assert_equal({}, ErrorScrubber.scrub_user(nil))
  end

  test "before_send scrubs a whole event: message, exception, request, extras, tags and breadcrumbs" do
    config = Sentry::Configuration.new
    config.dsn = "http://public:secret@sentry.localdomain/sentry/42"
    event = Sentry::ErrorEvent.new(configuration: config)
    event.message = "failed for jane@example.com"
    event.extra = { "email" => "jane@example.com", "context" => "Bearer abcdef" }
    event.tags = { "template" => "reset_password" }
    event.user = { id: 3, role: "jobseeker", email: "jane@example.com" }
    event.add_exception_interface(RuntimeError.new("token=zzz for jane@example.com"), mechanism: Sentry::Mechanism.new)
    event.rack_env = (Rack::MockRequest.env_for(
      "https://api.verse.test/api/auth/verify-email?token=s3cr3t",
      "HTTP_AUTHORIZATION" => "Bearer live-token", "HTTP_COOKIE" => "session=abc", "REMOTE_ADDR" => "203.0.113.9"
    ))
    event.breadcrumbs = Sentry::BreadcrumbBuffer.new
    event.breadcrumbs.record(Sentry::Breadcrumb.new(message: "GET /unsubscribe?token=abc", data: { "email" => "x@y.io" }))

    ErrorScrubber.before_send(event, {})
    payload = event.to_json_compatible.to_json

    assert_no_match(/jane@example\.com|s3cr3t|live-token|session=abc|203\.0\.113\.9|token=zzz|token=abc|x@y\.io/, payload)
    assert_equal({ id: 3, role: "jobseeker" }, event.user)
    assert_equal "reset_password", event.tags["template"]
    assert_nil event.request.data
    assert_nil event.request.cookies
  end
end
