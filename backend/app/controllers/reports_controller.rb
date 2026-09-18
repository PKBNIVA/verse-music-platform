class ReportsController < ApplicationController
  def create
    return unless authenticate!
    report = Report.create!(reporter: current_user, entity_type: params[:entityType], entity_id: params[:entityId], reason: params[:reason], details: params[:details], status: "open")
    audit!("report.create", report)
    render json: { id: report.id }, status: :created
  end
end
