class VerificationRequestsController < ApplicationController
  def create
    return unless authenticate!
    request = VerificationRequest.create!(user: current_user, kind: params[:kind], evidence_url: params[:evidenceUrl], note: params[:note])
    render json: { id: request.id }, status: :created
  end
end
