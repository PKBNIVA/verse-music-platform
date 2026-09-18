class HealthController < ApplicationController
  def show
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render json: { ok: true, service: "verse-rails", time: Time.current.iso8601 }
  rescue StandardError
    render json: { ok: false, service: "verse-rails", time: Time.current.iso8601 }, status: :service_unavailable
  end

  def readiness
    checks = {
      database: { ok: ActiveRecord::Base.connection.active?, engine: "postgresql" },
      frontendUrl: { ok: ENV["FRONTEND_URL"].present? },
      allowedOrigins: { ok: ENV["ALLOWED_ORIGINS"].present? },
      storage: { ok: !Rails.env.production? || ENV["AWS_BUCKET"].present?, provider: ENV["AWS_BUCKET"].present? ? "s3" : "local" },
      adminPassword: { ok: !Rails.env.production? || ENV.fetch("ADMIN_PASSWORD", "").length >= 14 },
      demoData: { ok: !Rails.env.production? || ENV["SEED_DEMO_DATA"] != "true" }
    }
    render json: { ok: checks.values.all? { _1[:ok] }, environment: Rails.env, checks: }, status: checks.values.all? { _1[:ok] } ? :ok : :service_unavailable
  end
end
