require "test_helper"
require "minitest/mock"
require_relative "../support/sentry_test_support"

class ErrorReporterTest < ActiveSupport::TestCase
  include SentryTestSupport

  class FlakyJob < ApplicationJob
    class Boom < StandardError; end
    class Blip < StandardError; end
    discard_on ArgumentError
    retry_on Boom, attempts: 1, wait: 0
    retry_on Blip, attempts: 3, wait: 0

    def perform(email, sealed_token, mode)
      raise ArgumentError, "bad input for #{email}" if mode == "discard"
      raise Boom, "provider down" if mode == "retry"
      raise Blip, "transient" if mode == "blip"
      raise "unexpected failure" if mode == "crash"
    end
  end

  test "the initializer is inert in tests and without a DSN" do
    refute Sentry.initialized?
    refute ErrorReporter.enabled?
    refute VerseSentry.enabled_by_env?({}, ActiveSupport::EnvironmentInquirer.new("production"))
    refute VerseSentry.enabled_by_env?({ "SENTRY_DSN" => "  " }, ActiveSupport::EnvironmentInquirer.new("production"))
    refute VerseSentry.enabled_by_env?({ "SENTRY_DSN" => SentryTestSupport::DUMMY_DSN }, ActiveSupport::EnvironmentInquirer.new("test"))
    assert VerseSentry.enabled_by_env?({ "SENTRY_DSN" => SentryTestSupport::DUMMY_DSN }, ActiveSupport::EnvironmentInquirer.new("production"))
  end

  test "configuration reads environment, release and a bounded trace rate, and keeps PII collection off" do
    config = Sentry::Configuration.new
    VerseSentry.configure(config, env: {
      "SENTRY_DSN" => SentryTestSupport::DUMMY_DSN, "SENTRY_ENVIRONMENT" => "staging",
      "RAILWAY_GIT_COMMIT_SHA" => "0123456789abcdef", "SENTRY_TRACES_SAMPLE_RATE" => "0.25"
    })
    assert_equal "staging", config.environment
    assert_equal "0123456789abcdef", config.release
    assert_in_delta 0.25, config.traces_sample_rate
    refute config.send_default_pii
    refute config.data_collection.user_info
    refute config.data_collection.queues
    assert_equal [], config.data_collection.http_bodies
    %w[ActiveRecord::RecordNotFound ActiveRecord::RecordInvalid ActionController::RoutingError ActionController::ParameterMissing ActionController::BadRequest].each do |name|
      assert_includes config.excluded_exceptions, name
    end

    assert_equal 0.0, VerseSentry.traces_sample_rate(nil)
    assert_equal 0.0, VerseSentry.traces_sample_rate("lots")
    assert_equal 1.0, VerseSentry.traces_sample_rate("7")
    default = Sentry::Configuration.new
    VerseSentry.configure(default, env: { "SENTRY_DSN" => SentryTestSupport::DUMMY_DSN })
    assert_equal Rails.env.to_s, default.environment
    assert_equal 0.0, default.traces_sample_rate
  end

  test "capture is a no-op without a DSN" do
    assert_nil ErrorReporter.capture(RuntimeError.new("boom"), tags: { source: "test" }, userEmail: "a@b.io")
    assert_nil ErrorReporter.set_user(User.new(id: 1, role: "admin"))
  end

  test "capture sends the exception with scrubbed tags and context" do
    with_sentry do
      event = ErrorReporter.capture(RuntimeError.new("delivery to jane@example.com failed"), tags: { source: "email_delivery_failed", template: "verify_email" },
        link: "https://verse.test/verify-email?token=abc123", recipientEmail: "jane@example.com", attempt: 2)
      assert event
      assert_equal 1, sentry_events.size
      payload = sentry_payloads.first
      assert_equal "email_delivery_failed", payload.dig("tags", "source")
      assert_equal "verify_email", payload.dig("tags", "template")
      assert_equal "https://verse.test/verify-email?token=[Filtered]", payload.dig("extra", "link")
      assert_equal "[Filtered]", payload.dig("extra", "recipientEmail")
      assert_equal 2, payload.dig("extra", "attempt")
      assert_match(/\Adelivery to \[email\] failed/, payload.dig("exception", "values", 0, "value"))
      assert_no_match(/jane@example|abc123/, payload.to_json)
    end
  end

  test "an exception already reported (e.g. by after_discard, then GoodJob's thread hook) is sent once" do
    with_sentry do
      error = RuntimeError.new("job exploded")
      ErrorReporter.capture(error, tags: { source: "active_job" })
      GoodJob._on_thread_error(error)
      assert_equal 1, sentry_events.size
    end
  end

  test "expected client errors are never sent" do
    with_sentry do
      assert_nil ErrorReporter.capture(ActiveRecord::RecordNotFound.new("nope"))
      assert_nil ErrorReporter.capture(ActionController::ParameterMissing.new(:name))
      assert_empty sentry_events
    end
  end

  test "reporting never raises into the caller" do
    with_sentry do
      Sentry.stub(:capture_exception, ->(*) { raise IOError, "transport broke" }) do
        assert_nil ErrorReporter.capture(RuntimeError.new("boom"))
      end
    end
  end

  test "discarded, retry-exhausted and crashed jobs report class and id only, never arguments" do
    sealed = "sealed-#{SecureRandom.hex(8)}" # built at runtime so it never appears in source context lines
    with_sentry do
      discarded = FlakyJob.new("artist@example.com", sealed, "discard")
      discarded.perform_now

      exhausted = FlakyJob.new("artist@example.com", sealed, "retry")
      assert_raises(FlakyJob::Boom) { exhausted.perform_now }

      crashed = FlakyJob.new("artist@example.com", sealed, "crash")
      assert_raises(RuntimeError) { crashed.perform_now }

      payloads = sentry_payloads
      assert_equal 3, payloads.size
      assert_equal [discarded.job_id, exhausted.job_id, crashed.job_id], payloads.map { _1.dig("tags", "job_id") }
      payloads.each do |payload|
        assert_equal FlakyJob.name, payload.dig("tags", "job_class")
        assert_equal "active_job", payload.dig("tags", "source")
        assert_equal %w[job_class job_id], payload["extra"].keys.sort
        serialized = payload.to_json
        assert_no_match(/artist@example|#{sealed}/, serialized)
        assert_nil payload.dig("contexts", "active_job", "arguments")
      end
    end
  end

  test "a job that will be retried, or succeeds, is not reported" do
    with_sentry do
      FlakyJob.new("artist@example.com", "sealed", "blip").perform_now
      FlakyJob.new("artist@example.com", "sealed", "ok").perform_now
      assert_empty sentry_events
    end
  end
end
