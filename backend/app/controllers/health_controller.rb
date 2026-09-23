class HealthController < ApplicationController
  RELEASE = ENV.fetch("RAILWAY_GIT_COMMIT_SHA", ENV.fetch("RENDER_GIT_COMMIT", "unknown")).freeze

  def show
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render json: health_payload(true)
  rescue StandardError
    render json: health_payload(false), status: :service_unavailable
  end

  def readiness
    checks = {
      database: { ok: ActiveRecord::Base.connection.active?, required: true, engine: "postgresql" },
      frontendUrl: { ok: ENV["FRONTEND_URL"].present?, required: true },
      allowedOrigins: { ok: ENV["ALLOWED_ORIGINS"].present?, required: true },
      adminPassword: { ok: !Rails.env.production? || ENV.fetch("ADMIN_PASSWORD", "").length >= 14, required: true },
      demoData: { ok: !Rails.env.production? || ENV["SEED_DEMO_DATA"] != "true", required: true },
      storage: { ok: !Rails.env.production? || ENV["AWS_BUCKET"].present? || ENV["PERSISTENT_UPLOADS"] == "true", required: false, provider: ENV["AWS_BUCKET"].present? ? "s3-compatible" : ENV["PERSISTENT_UPLOADS"] == "true" ? "persistent-disk" : "disabled" },
      payments: { ok: !Rails.env.production? || ENV.values_at("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET").all?(&:present?), required: false, provider: ENV["RAZORPAY_KEY_ID"].present? ? "razorpay" : "disabled" },
      emailDelivery: { ok: !Rails.env.production? || (ENV["RESEND_API_KEY"].present? && ENV["EMAIL_FROM"].present?) || ENV["EMAIL_DELIVERY_WEBHOOK"].present?, required: ENV["REQUIRE_EMAIL_VERIFICATION"] == "true", provider: ENV["RESEND_API_KEY"].present? ? "resend" : ENV["EMAIL_DELIVERY_WEBHOOK"].present? ? "webhook" : "disabled" }
    }
    core_ready = checks.values.select { _1[:required] }.all? { _1[:ok] }
    render json: health_payload(core_ready).merge(integrationsReady: checks.values.all? { _1[:ok] }, environment: Rails.env, checks:), status: core_ready ? :ok : :service_unavailable
  end

  private

  def health_payload(ok)
    { ok:, service: "verse-rails", release: RELEASE.first(12), time: Time.current.iso8601 }
  end
end
