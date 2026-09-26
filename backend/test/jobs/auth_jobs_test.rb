require "test_helper"
require "minitest/mock"

class AuthJobsTest < ActiveJob::TestCase
  Response = Struct.new(:status, :body) do
    def success? = status.between?(200, 299)
  end

  FakeRequest = Struct.new(:headers, :body, :options)
  LINK = "https://verse.example/reset-password?token=secret-reset-token".freeze

  setup do
    @user = User.create!(name: "Mail Recipient", email: "mail-recipient@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
  end

  test "email job delivers the decrypted link to the user's current address" do
    sent = []
    transport = lambda do |url, &configure|
      request = FakeRequest.new({}, nil, Struct.new(:open_timeout, :timeout).new)
      configure.call(request)
      sent << [url, JSON.parse(request.body)]
      Response.new(202, "{}")
    end

    with_webhook do
      Faraday.stub(:post, transport) { EmailDeliveryJob.perform_now(@user.id, "reset_password", EmailDeliveryJob.seal(LINK)) }
    end

    assert_equal 1, sent.size
    url, body = sent.first
    assert_equal "https://email-hook.example.invalid/send", url
    assert_equal "mail-recipient@example.com", body["to"]
    assert_equal LINK, body.dig("data", "link")
    assert_no_enqueued_jobs
  end

  test "email job is retried on timeout and gives up after five attempts" do
    calls = 0
    timeout = ->(*) { calls += 1; raise Faraday::TimeoutError, "timed out" }

    with_webhook do
      Faraday.stub(:post, timeout) do
        assert_enqueued_jobs 1, only: EmailDeliveryJob do
          EmailDeliveryJob.perform_now(@user.id, "reset_password", EmailDeliveryJob.seal(LINK))
        end
        assert_equal 1, calls

        clear_enqueued_jobs
        job = EmailDeliveryJob.new(@user.id, "reset_password", EmailDeliveryJob.seal(LINK))
        4.times { job.perform_now }
        assert_enqueued_jobs 4, only: EmailDeliveryJob
        assert_raises(Faraday::TimeoutError) { job.perform_now }
        assert_equal 5, job.executions
      end
    end
    assert_equal 6, calls
  end

  test "email job retries provider 5xx and logs the status" do
    log = capture_log do
      with_webhook do
        Faraday.stub(:post, ->(*) { Response.new(503, "echo #{LINK}") }) do
          assert_enqueued_jobs 1, only: EmailDeliveryJob do
            EmailDeliveryJob.perform_now(@user.id, "reset_password", EmailDeliveryJob.seal(LINK))
          end
        end
      end
    end
    assert_includes log, '"status":503'
    assert_not_includes log, "secret-reset-token"
  end

  test "email job does not retry provider 4xx and never logs the response body" do
    log = capture_log do
      with_env("BREVO_API_KEY" => "test-key", "BREVO_SENDER_EMAIL" => "sender@example.invalid", "EMAIL_DELIVERY_WEBHOOK" => nil, "RESEND_API_KEY" => nil) do
        Faraday.stub(:post, ->(*) { Response.new(400, "invalid #{LINK}") }) do
          assert_no_enqueued_jobs do
            EmailDeliveryJob.perform_now(@user.id, "reset_password", EmailDeliveryJob.seal(LINK))
          end
        end
      end
    end
    assert_includes log, '"provider":"brevo"'
    assert_includes log, '"status":400'
    assert_not_includes log, "secret-reset-token"
    assert_not_includes log, "mail-recipient@example.com"
  end

  test "email job skips missing users and tampered links without calling the provider" do
    with_webhook do
      Faraday.stub(:post, ->(*) { flunk "provider must not be called" }) do
        EmailDeliveryJob.perform_now("missing-user", "reset_password", EmailDeliveryJob.seal(LINK))
        EmailDeliveryJob.perform_now(@user.id, "reset_password", "tampered--data")
      end
    end
    assert_no_enqueued_jobs
  end

  test "sealed links are encrypted" do
    sealed = EmailDeliveryJob.seal(LINK)
    assert_not_includes sealed, "secret-reset-token"
    assert_not_includes Base64.decode64(sealed.split("--").first), "secret-reset-token"
    assert_equal LINK, EmailDeliveryJob.unseal(sealed)
  end

  test "cleanup deletes expired sessions and stale email tokens only" do
    now = Time.current
    live = @user.sessions.create!(token_digest: "live", expires_at: now + 1.day)
    @user.sessions.create!(token_digest: "expired", expires_at: now - 1.minute)

    fresh_unused = token("fresh", expires_at: now + 1.hour)
    recently_expired = token("recent-expired", expires_at: now - 2.days)
    recently_used = token("recent-used", expires_at: now + 1.hour, used_at: now - 1.day)
    token("old-expired", expires_at: now - 8.days)
    token("old-used", expires_at: now + 1.hour, used_at: now - 8.days)

    AuthCleanupJob.perform_now(now)

    assert_equal [live.id], @user.sessions.pluck(:id)
    assert_equal [fresh_unused, recently_expired, recently_used].map(&:id).sort, @user.email_tokens.pluck(:id).sort
  end

  test "cleanup job is scheduled daily through GoodJob cron" do
    cron = Rails.application.config.good_job.cron.fetch(:auth_cleanup)
    assert_equal "AuthCleanupJob", cron.fetch(:class)
    assert_match(/\A\d+ \d+ \* \* \*\z/, cron.fetch(:cron))
  end

  private

  def token(digest, expires_at:, used_at: nil)
    @user.email_tokens.create!(purpose: "reset_password", token_digest: digest, expires_at:, used_at:)
  end

  def with_webhook(&)
    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send", "BREVO_API_KEY" => nil, "RESEND_API_KEY" => nil, &)
  end

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
