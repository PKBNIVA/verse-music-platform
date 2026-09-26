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
      backgroundJobs: background_jobs_check,
      storage: storage_check,
      payments: check(payments_ready?, required: false,
        provider: ENV["RAZORPAY_KEY_ID"].present? ? "razorpay" : "disabled", mode: RazorpayConfig.mode),
      emailDelivery: check(!Rails.env.production? || EmailDelivery.brevo_configured? || (ENV["RESEND_API_KEY"].present? && ENV["EMAIL_FROM"].present?) || ENV["EMAIL_DELIVERY_WEBHOOK"].present?,
        required: ENV["REQUIRE_EMAIL_VERIFICATION"] == "true",
        provider: EmailDelivery.brevo_configured? ? "brevo" : ENV["RESEND_API_KEY"].present? ? "resend" : ENV["EMAIL_DELIVERY_WEBHOOK"].present? ? "webhook" : "disabled")
    }
  end

  def core_ready?(checks)
    checks.values.select { _1[:required] }.all? { _1[:ok] }
  end

  def optional_integrations_ready?(checks)
    checks.values.reject { _1[:required] }.all? { _1[:ok] }
  end

  private

  # Configuration problems are reported as fixed codes (never values) so the admin
  # health view can say *what* is wrong without echoing credentials or hostnames.
  def storage_check
    direct = UploadStorage.direct?
    problems = UploadStorage.configuration_problems
    ok = direct ? problems.empty? : (!Rails.env.production? || ENV["PERSISTENT_UPLOADS"] == "true")
    details = { provider: direct ? "s3-compatible" : ENV["PERSISTENT_UPLOADS"] == "true" ? "persistent-disk" : Rails.env.production? ? "disabled" : "local-disk" }
    details[:uploadMethod] = UploadStorage.upload_method if direct
    details[:problems] = problems if problems.any?
    check(ok, required: false, **details)
  end

  def payments_ready?
    return false if RazorpayConfig.key_present? && !RazorpayConfig.key_mode_allowed?
    !Rails.env.production? || (RazorpayConfig.usable? && ENV["RAZORPAY_WEBHOOK_SECRET"].present?)
  end

  def background_jobs_check
    adapter = ActiveJob::Base.queue_adapter_name
    schema_ready = @connection_provider.call.data_source_exists?("good_jobs")
    check(!Rails.env.production? || (adapter == "good_job" && schema_ready), required: Rails.env.production?, adapter:, schemaReady: schema_ready,
      executionMode: ENV.fetch("GOOD_JOB_EXECUTION_MODE", Rails.env.production? ? "async" : "external"))
  rescue StandardError
    check(false, required: Rails.env.production?, adapter: adapter || "unknown", schemaReady: false)
  end

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
