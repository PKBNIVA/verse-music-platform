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
  end
end
