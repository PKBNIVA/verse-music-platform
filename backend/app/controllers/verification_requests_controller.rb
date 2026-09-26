class VerificationRequestsController < ApplicationController
  FIELD_LIMITS = { evidenceUrl: 2_048, note: 2_000 }.freeze

  def create
    return unless authenticate!
    expected_kind = { "jobseeker" => "professional", "employer" => "organization" }[current_user.role]
    unless expected_kind && params[:kind] == expected_kind
      return render_error("Verification kind must match your account type.", :bad_request, "INVALID_VERIFICATION_KIND")
    end
    invalid = FIELD_LIMITS.find { |key, limit| !params[key].nil? && (!params[key].is_a?(String) || params[key].length > limit) }&.first
    return render_error("#{invalid} must be text of at most #{FIELD_LIMITS[invalid]} characters.", :unprocessable_content, "INVALID_VERIFICATION_REQUEST") if invalid

    request = VerificationRequest.create!(user: current_user, kind: params[:kind], evidence_url: params[:evidenceUrl].presence, note: params[:note])
    render json: { id: request.id }, status: :created
  end
end
