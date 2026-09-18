class ConversationsController < ApplicationController
  before_action -> { authenticate! }
  def index
    rows = Conversation.where("candidate_id = ? OR employer_id = ?", current_user.id, current_user.id).includes(:candidate, :employer, :job, :messages).order(updated_at: :desc)
    render json: { conversations: rows.map { |c| { id: c.id, candidateName: c.candidate.name, employerName: c.employer.name, jobTitle: c.job&.title, lastMessage: c.messages.max_by(&:created_at)&.body } } }
  end
  def create
    job = Job.find_by(id: params[:jobId])
    candidate = params[:candidateId].present? ? User.jobseeker.find(params[:candidateId]) : current_user
    employer = params[:employerId].present? ? User.find(params[:employerId]) : (job&.employer || current_user)
    return render_error("You cannot create this conversation.", :forbidden) unless [candidate.id, employer.id].include?(current_user.id)
    conversation = Conversation.find_or_create_by!(candidate:, employer:, job:)
    render json: { id: conversation.id, conversation: { id: conversation.id } }, status: :created
  end
end
