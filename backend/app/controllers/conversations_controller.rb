class ConversationsController < ApplicationController
  before_action -> { authenticate! }
  def index
    rows = Conversation.where("candidate_id = ? OR employer_id = ?", current_user.id, current_user.id).includes(:candidate, :employer, :job, :messages).order(updated_at: :desc)
    render json: { conversations: rows.map { |c| { id: c.id, candidateName: c.candidate.name, employerName: c.employer.name, jobTitle: c.job&.title, lastMessage: c.messages.max_by(&:created_at)&.body } } }
  end
  def create
    candidate = User.jobseeker.find(params[:candidateId]); employer = User.find(params[:employerId] || current_user.id)
    return render_error("You cannot create this conversation.", :forbidden) unless [candidate.id, employer.id].include?(current_user.id)
    conversation = Conversation.find_or_create_by!(candidate:, employer:, job_id: params[:jobId])
    render json: { id: conversation.id }, status: :created
  end
end
