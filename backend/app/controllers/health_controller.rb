class HealthController < ApplicationController
  RELEASE = ENV.fetch("RAILWAY_GIT_COMMIT_SHA", ENV.fetch("RENDER_GIT_COMMIT", "unknown")).freeze

  def show
    render json: health_payload(true)
  end

  def readiness
    checker = ReadinessChecks.new
    core_ready = checker.core_ready?(checker.call)
    render json: health_payload(core_ready), status: core_ready ? :ok : :service_unavailable
  end

  private

  # A not-ready answer also carries the API-wide {error, code} fields so clients and uptime
  # probes can treat it like any other error response.
  def health_payload(ok)
    payload = { ok:, service: "verse-rails", release: RELEASE.first(12), time: Time.current.iso8601 }
    ok ? payload : payload.merge(error: "Service is not ready.", code: "NOT_READY")
  end
end
