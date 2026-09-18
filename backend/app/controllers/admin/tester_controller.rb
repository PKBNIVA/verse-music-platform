module Admin
  class TesterController < BaseController
    def index
      checks = []
      check = ->(name, pass, detail, severity = "critical") { checks << { name:, pass: !!pass, detail:, severity: } }
      check.call("PostgreSQL connection", ActiveRecord::Base.connection.active?, ActiveRecord::Base.connection_db_config.adapter)
      %w[users profiles jobs applications portfolio_items acts booking_requests subscriptions recent_activities crew_plans audit_logs].each do |table|
        check.call("Table: #{table}", ActiveRecord::Base.connection.data_source_exists?(table), "Available", "high")
      end
      check.call("Production frontend URL", !Rails.env.production? || ENV["FRONTEND_URL"].to_s.start_with?("https://"), ENV["FRONTEND_URL"].presence || "Not configured", "high")
      check.call("Object storage", !Rails.env.production? || ENV["AWS_BUCKET"].present?, ENV["AWS_BUCKET"].present? ? "Configured" : "Not configured", "medium")
      check.call("Duplicate user emails", User.group("lower(email)").having("COUNT(*) > 1").none?, "None", "high")
      passed = checks.count { _1[:pass] }
      render json: { summary: { passed:, total: checks.length, failed: checks.length - passed, healthy: checks.all? { _1[:pass] || _1[:severity] == "medium" } }, checks:, generatedAt: Time.current.iso8601 }
    end
  end
end
