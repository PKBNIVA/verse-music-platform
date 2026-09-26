module Admin
  class HealthController < BaseController
    RELEASE = ENV.fetch("RAILWAY_GIT_COMMIT_SHA", ENV.fetch("RENDER_GIT_COMMIT", "unknown")).freeze

    def show
      checker = ReadinessChecks.new
      checks = checker.call
      core_ready = checker.core_ready?(checks)

      render json: {
        ok: core_ready,
        service: "verse-rails",
        release: RELEASE.first(12),
        time: Time.current.iso8601,
        environment: Rails.env,
        coreReady: core_ready,
        optionalIntegrationsReady: checker.optional_integrations_ready?(checks),
        checks:
      }, status: core_ready ? :ok : :service_unavailable
    end

    # Raised (and captured, never propagated) by the admin "send test error" check.
    class SentryTestError < StandardError; end

    # Proves error alerting end to end: raises a tagged exception and reports it.
    # `captured` is false when SENTRY_DSN is unset (the reporter is inert).
    def sentry_test
      event = begin
        raise SentryTestError, "Verse Sentry test error (triggered by an admin; safe to resolve)"
      rescue SentryTestError => error
        ErrorReporter.capture(error, tags: { source: "admin_sentry_test", verse_test: "true" }, level: :error)
      end
      captured = event.present?
      audit!("admin.sentry_test", nil, { captured: })
      render json: { captured:, eventId: event&.event_id, release: RELEASE.first(12) }
    end
  end
end
