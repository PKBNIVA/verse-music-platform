require "timeout"

class ReadinessChecks
  DATABASE_TIMEOUT_SECONDS = 2.5

  def initialize(connection_provider: -> { ActiveRecord::Base.connection })
    @connection_provider = connection_provider
  end

  def call
    {
      database: database_check,
      frontendUrl: check(ENV["FRONTEND_URL"].present?, required: true),
      allowedOrigins: check(ENV["ALLOWED_ORIGINS"].present?, required: true),
      adminPassword: check(!Rails.env.production? || ENV.fetch("ADMIN_PASSWORD", "").length >= 14, required: true),
      demoData: check(!Rails.env.production? || ENV["SEED_DEMO_DATA"] != "true", required: true),
      storage: check(!Rails.env.production? || ENV["AWS_BUCKET"].present? || ENV["PERSISTENT_UPLOADS"] == "true", required: false,
        provider: ENV["AWS_BUCKET"].present? ? "s3-compatible" : ENV["PERSISTENT_UPLOADS"] == "true" ? "persistent-disk" : "disabled"),
      payments: check(!Rails.env.production? || ENV.values_at("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET").all?(&:present?), required: false,
        provider: ENV["RAZORPAY_KEY_ID"].present? ? "razorpay" : "disabled"),
      emailDelivery: check(!Rails.env.production? || (ENV["RESEND_API_KEY"].present? && ENV["EMAIL_FROM"].present?) || ENV["EMAIL_DELIVERY_WEBHOOK"].present?,
        required: ENV["REQUIRE_EMAIL_VERIFICATION"] == "true",
        provider: ENV["RESEND_API_KEY"].present? ? "resend" : ENV["EMAIL_DELIVERY_WEBHOOK"].present? ? "webhook" : "disabled")
    }
  end

  def core_ready?(checks)
    checks.values.select { _1[:required] }.all? { _1[:ok] }
  end

  def optional_integrations_ready?(checks)
    checks.values.reject { _1[:required] }.all? { _1[:ok] }
  end

  private

  def database_check
    connection = @connection_provider.call
    result = Timeout.timeout(DATABASE_TIMEOUT_SECONDS) do
      connection.transaction(requires_new: true) do
        connection.execute("SET LOCAL statement_timeout = '2000ms'") if connection.adapter_name == "PostgreSQL"
        connection.select_value("SELECT 1")
      end
    end
    check(result.to_i == 1, required: true, engine: "postgresql")
  rescue StandardError
    check(false, required: true, engine: "postgresql")
  end

  def check(ok, required:, **details)
    { ok: !!ok, required:, **details }
  end
end
