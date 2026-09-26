require "sentry/test_helper"

# Runs a block with the real Sentry SDK initialised through VerseSentry.configure, but
# with a DummyTransport: events are kept in memory and nothing leaves the process.
module SentryTestSupport
  DUMMY_DSN = "http://public:secret@sentry.localdomain/sentry/42".freeze

  def with_sentry(env = {})
    Sentry.init do |config|
      VerseSentry.configure(config, env: { "SENTRY_DSN" => DUMMY_DSN, "SENTRY_ENVIRONMENT" => "test" }.merge(env))
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
      config.auto_session_tracking = false
      config.sdk_logger = ::Logger.new(nil)
    end
    yield
  ensure
    Sentry::TestHelper.reset_sentry_globals!
  end

  def sentry_events
    Sentry.get_main_hub.current_client.transport.events
  end

  # The JSON-ready payload the transport would send.
  def sentry_payloads
    sentry_events.map { |event| JSON.parse(event.to_json_compatible.to_json) }
  end
end
