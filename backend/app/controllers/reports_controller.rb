class ReportsController < ApplicationController
  include UserRateLimit

  CREATE_LIMIT_PER_HOUR = 30
  FIELD_LIMITS = { entityType: 40, entityId: 120, reason: 200, details: 5_000 }.freeze

  def create
    return unless authenticate!
    invalid = FIELD_LIMITS.keys.find { |key| params.key?(key) && !params[key].is_a?(String) }
    return render_error("#{invalid} must be text.", :unprocessable_content, "INVALID_REPORT") if invalid
    missing = %i[entityType entityId reason].find { params[_1].blank? }
    return render_error("#{missing} is required.", :unprocessable_content, "INVALID_REPORT") if missing
    too_long = FIELD_LIMITS.find { |key, limit| params[key].to_s.length > limit }&.first
    return render_error("#{too_long} is too long.", :unprocessable_content, "INVALID_REPORT") if too_long
    return unless within_user_rate_limit?("report", limit: CREATE_LIMIT_PER_HOUR, period: 1.hour)

    report = Report.create!(reporter: current_user, entity_type: params[:entityType], entity_id: params[:entityId], reason: params[:reason], details: params[:details], status: "open")
    audit!("report.create", report)
    render json: { id: report.id }, status: :created
  end
end
