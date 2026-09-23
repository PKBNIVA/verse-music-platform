module Admin
  class TesterController < BaseController
    def index
      checks = []
      check = ->(name, pass, detail, severity = "critical") { checks << { name:, pass: !!pass, detail:, severity: } }
      query_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.connection.select_value("SELECT 1")
      query_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - query_started) * 1_000).round(1)
      check.call("PostgreSQL connection", ActiveRecord::Base.connection.active?, "#{ActiveRecord::Base.connection_db_config.adapter} · #{query_ms} ms")
      %w[users profiles jobs applications portfolio_items acts booking_requests subscriptions recent_activities crew_plans audit_logs].each do |table|
        check.call("Table: #{table}", ActiveRecord::Base.connection.data_source_exists?(table), "Available", "high")
      end
      check.call("Production frontend URL", !Rails.env.production? || ENV["FRONTEND_URL"].to_s.start_with?("https://"), ENV["FRONTEND_URL"].presence || "Not configured", "high")
      persistent_storage = ENV["PERSISTENT_UPLOADS"] == "true" && Rails.root.join("storage").writable?
      storage_ready = ENV["AWS_BUCKET"].present? || persistent_storage
      storage_detail = ENV["AWS_BUCKET"].present? ? "S3-compatible storage configured" : persistent_storage ? "Persistent disk writable" : "Not configured or not writable"
      check.call("Upload storage", !Rails.env.production? || storage_ready, storage_detail, "high")
      release = ENV.fetch("RAILWAY_GIT_COMMIT_SHA", ENV.fetch("RENDER_GIT_COMMIT", ""))
      check.call("Release traceability", !Rails.env.production? || release.present?, release.present? ? release.first(12) : "Commit SHA unavailable", "high")
      check.call("Email delivery", !Rails.env.production? || (ENV["RESEND_API_KEY"].present? && ENV["EMAIL_FROM"].present?) || ENV["EMAIL_DELIVERY_WEBHOOK"].present?, ENV["RESEND_API_KEY"].present? ? "Resend configured" : ENV["EMAIL_DELIVERY_WEBHOOK"].present? ? "Webhook configured" : "Not configured", "medium")
      check.call("Razorpay", !Rails.env.production? || ENV.values_at("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET").all?(&:present?), ENV["RAZORPAY_KEY_ID"].present? ? "Configured" : "Not configured", "medium")
      check.call("Duplicate user emails", User.group("lower(email)").having("COUNT(*) > 1").none?, "None", "high")
      invalid_payments = BookingPayment.where("amount <= 0").count
      check.call("Invalid booking payments", invalid_payments.zero?, "#{invalid_payments} invalid", "high")
      expired_sessions = Session.where("expires_at <= ?", Time.current).count
      check.call("Expired session backlog", expired_sessions < 1_000, "#{expired_sessions} pending cleanup", "low")
      required_indexes = %w[index_subscriptions_on_provider_subscription_id index_booking_payments_on_provider_order_id]
      present_indexes = ActiveRecord::Base.connection.indexes(:subscriptions).map(&:name) + ActiveRecord::Base.connection.indexes(:booking_payments).map(&:name)
      missing_indexes = required_indexes - present_indexes
      check.call("Payment idempotency indexes", missing_indexes.empty?, missing_indexes.empty? ? "Available" : "Migration pending", "high")
      passed = checks.count { _1[:pass] }
      render json: { summary: { passed:, total: checks.length, failed: checks.length - passed, healthy: checks.all? { _1[:pass] || %w[low medium].include?(_1[:severity]) }, databaseLatencyMs: query_ms }, checks:, generatedAt: Time.current.iso8601 }
    end
  end
end
