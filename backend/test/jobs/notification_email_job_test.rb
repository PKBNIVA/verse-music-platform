require "test_helper"
require "minitest/mock"

class NotificationEmailJobTest < ActiveJob::TestCase
  Response = Struct.new(:status, :body) do
    def success? = status.between?(200, 299)
  end
  FakeRequest = Struct.new(:headers, :body, :options)

  setup do
    @user = User.create!(name: "Notified Employer", email: "notified-employer@example.com", password: "StrongPass123!", role: "employer",
      status: "active", email_verified: true)
  end

  test "renders escaped content with a workspace link and posts it to the configured provider" do
    sent = []
    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send", "FRONTEND_URL" => "https://verse.example/") do
      Faraday.stub(:post, capture(sent)) do
        NotificationEmailJob.perform_now(@user.id, "new_message", { "name" => "<b>Mallory</b>", "path" => "/messages?c=abc" })
      end
    end

    url, body = sent.sole
    assert_equal "https://email-hook.example.invalid/send", url
    assert_equal ["notified-employer@example.com", "new_message"], body.values_at("to", "template")
    data = body.fetch("data")
    assert_equal "New message from <b>Mallory</b> on Verse", data["subject"]
    assert_includes data["html"], "&lt;b&gt;Mallory&lt;/b&gt;"
    assert_not_includes data["html"], "<b>Mallory"
    assert_includes data["html"], "https://verse.example/employer/messages?c=abc"
    assert_includes data["text"], "https://verse.example/employer/messages?c=abc"
  end

  test "uses Brevo when configured and never logs content" do
    sent = []
    logs = capture_logs do
      with_env("BREVO_API_KEY" => "brevo-key", "BREVO_SENDER_EMAIL" => "hello@verse.example") do
        Faraday.stub(:post, capture(sent, status: 400)) do
          NotificationEmailJob.perform_now(@user.id, "booking_enquiry", { "act" => "Night Owls", "name" => "Planner" })
        end
      end
    end

    url, body = sent.sole
    assert_equal "https://api.brevo.com/v3/smtp/email", url
    assert_equal "New booking enquiry for Night Owls", body["subject"]
    assert_includes body["htmlContent"], "/employer/bookings"
    assert_includes logs, "notification_email_skipped"
    assert_not_includes logs, "Night Owls"
    assert_not_includes logs, "notified-employer@example.com"
  end

  test "skips unverified, missing and unconfigured recipients and unknown templates without calling a provider" do
    unverified = User.create!(name: "Unverified", email: "unverified-notify@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    Faraday.stub(:post, ->(*) { flunk "provider must not be called" }) do
      with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
        NotificationEmailJob.perform_now(unverified.id, "booking_status", { "act" => "A", "status" => "viewed" })
        NotificationEmailJob.perform_now("missing", "booking_status", {})
        NotificationEmailJob.perform_now(@user.id, "not_a_template", {})
      end
      with_env("EMAIL_DELIVERY_WEBHOOK" => nil) do
        NotificationEmailJob.perform_now(@user.id, "booking_status", { "act" => "A", "status" => "viewed" })
      end
    end
    assert_no_enqueued_jobs # skips are final, not retried
  end

  test "retries provider outages" do
    with_env("EMAIL_DELIVERY_WEBHOOK" => "https://email-hook.example.invalid/send") do
      Faraday.stub(:post, ->(*) { Response.new(503, "down") }) do
        assert_enqueued_with(job: NotificationEmailJob) do
          NotificationEmailJob.perform_now(@user.id, "application_status", { "job" => "Gig", "status" => "Offer" })
        end
      end
    end
  end

  private

  def capture(sent, status: 202)
    lambda do |url, &configure|
      request = FakeRequest.new({}, nil, Struct.new(:open_timeout, :timeout).new)
      configure.call(request)
      sent << [url, JSON.parse(request.body)]
      Response.new(status, "{}")
    end
  end

  def capture_logs
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
