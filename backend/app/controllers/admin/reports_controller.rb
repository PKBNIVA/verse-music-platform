module Admin
  class ReportsController < BaseController
    def index = render(json: { reports: Report.includes(:reporter).order(created_at: :desc) })
    def update
      return render_error("Invalid report status.", :bad_request) unless %w[resolved dismissed].include?(params[:status])
      report = Report.find(params[:id]); report.update!(status: params[:status], resolved_by: current_user.id, resolved_at: Time.current); audit!("admin.report", report); render json: { ok: true }
    end
  end
end
