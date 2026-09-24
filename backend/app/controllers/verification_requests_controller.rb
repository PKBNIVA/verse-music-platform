class VerificationRequestsController < ApplicationController
  def create
    return unless authenticate!
    expected_kind = { "jobseeker" => "professional", "employer" => "organization" }[current_user.role]
    unless expected_kind && params[:kind] == expected_kind
      return render_error("Verification kind must match your account type.", :bad_request, "INVALID_VERIFICATION_KIND")
    end
    request = VerificationRequest.create!(user: current_user, kind: params[:kind], evidence_url: params[:evidenceUrl], note: params[:note])
    render json: { id: request.id }, status: :created
  end
end
