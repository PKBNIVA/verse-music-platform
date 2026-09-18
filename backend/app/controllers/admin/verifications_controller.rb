module Admin
  class VerificationsController < BaseController
    def index = render(json: { requests: VerificationRequest.includes(user: :profile).order(created_at: :desc) })
    def update
      return render_error("Invalid verification status.", :bad_request) unless %w[approved rejected].include?(params[:status])
      request_record = VerificationRequest.find(params[:id])
      request_record.transaction do
        request_record.update!(status: params[:status], reviewed_by: current_user.id, reviewed_at: Time.current)
        request_record.user.profile&.update!(verified: true) if params[:status] == "approved"
      end
      Notification.create!(user: request_record.user, kind: "verification", title: "Verification update", body: "Your verification request was #{params[:status]}.")
      render json: { ok: true }
    end
  end
end
