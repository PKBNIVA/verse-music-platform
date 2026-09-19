class ConversationsController < ApplicationController
  before_action -> { authenticate! }
  def index
    rows = Conversation.where("candidate_id = ? OR employer_id = ?", current_user.id, current_user.id).includes(:candidate, :employer, :job, :messages).order(updated_at: :desc)
    render json: { conversations: rows.map { |c| { id: c.id, candidateName: c.candidate.name, employerName: c.employer.name, jobTitle: c.job&.title, lastMessage: c.messages.max_by(&:created_at)&.body } } }
  end
  def create
    job = Job.find_by(id: params[:jobId])
    candidate = resolve_candidate
    employer = resolve_employer(job)
    return render_error("You cannot create this conversation.", :forbidden) unless candidate && employer
    return render_error("You cannot message yourself.", :unprocessable_entity) if candidate.id == employer.id
    return render_error("You cannot create this conversation.", :forbidden) unless [candidate.id, employer.id].include?(current_user.id)

    if job
      return render_error("Conversation does not match this opportunity.", :unprocessable_entity) unless employer.id == job.employer_id
      if current_user.id == employer.id && !Application.exists?(job:, candidate:)
        return render_error("You can message candidates who applied to this opportunity.", :forbidden)
      end
      if current_user.id == candidate.id && !job.published?
        return render_error("This opportunity is not open for messages.", :forbidden)
      end
    end

    conversation = Conversation.find_or_create_by!(candidate:, employer:, job:)
    render json: { id: conversation.id, conversation: { id: conversation.id } }, status: :created
  end

  private

  def resolve_candidate
    id = params[:candidateId].presence || (current_user.jobseeker? ? current_user.id : nil)
    User.jobseeker.active.find_by(id:)
  end

  def resolve_employer(job)
    id = job&.employer_id || params[:employerId].presence || (params[:candidateId].present? ? current_user.id : nil)
    User.active.where.not(role: "admin").find_by(id:)
  end
end
