class ConversationsController < ApplicationController
  include UserRateLimit

  CREATE_LIMIT_PER_HOUR = 20
  PREVIEW_LENGTH = 200
  # Latest message column per conversation, served by the messages(conversation_id, created_at) index.
  LATEST_MESSAGE = "(SELECT %s FROM messages WHERE messages.conversation_id = conversations.id " \
    "ORDER BY messages.created_at DESC LIMIT 1)".freeze

  before_action -> { authenticate! }
  def index
    unread_sql = Conversation.sanitize_sql_array([
      "(SELECT COUNT(*) FROM messages WHERE messages.conversation_id = conversations.id " \
      "AND messages.read_at IS NULL AND messages.sender_id <> ?) AS unread_count", current_user.id
    ])
    rows = Conversation.where("candidate_id = ? OR employer_id = ?", current_user.id, current_user.id)
      .select(Conversation.arel_table[Arel.star],
        "#{format(LATEST_MESSAGE, "LEFT(messages.body, #{PREVIEW_LENGTH})")} AS last_message_body",
        "#{format(LATEST_MESSAGE, 'messages.created_at')} AS last_message_at",
        "#{format(LATEST_MESSAGE, 'messages.sender_id')} AS last_message_sender_id",
        unread_sql)
      .includes(:candidate, :employer, :job).order(updated_at: :desc)
    render json: { conversations: rows.map { serialize(_1) } }
  end

  def create
    return unless within_user_rate_limit?("conversation", limit: CREATE_LIMIT_PER_HOUR, period: 1.hour)
    return create_for_booking if params[:bookingId].present?

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

    open_conversation(candidate:, employer:, job:)
  end

  private

  # Booking parties may message each other: the act owner is the talent side
  # (candidate) and the requester is the hiring side (employer).
  def create_for_booking
    booking = BookingRequest.includes(:act).find_by(id: params[:bookingId])
    return render_error("Booking not found", :not_found) unless booking && [booking.requester_id, booking.act.owner_id].include?(current_user.id)

    candidate = User.active.find_by(id: booking.act.owner_id)
    employer = User.active.find_by(id: booking.requester_id)
    return render_error("You cannot create this conversation.", :forbidden) unless candidate && employer
    return render_error("You cannot message yourself.", :unprocessable_entity) if candidate.id == employer.id

    open_conversation(candidate:, employer:, job: nil)
  end

  def open_conversation(candidate:, employer:, job:)
    conversation = begin
      Conversation.find_or_create_by!(candidate:, employer:, job:)
    rescue ActiveRecord::RecordNotUnique
      Conversation.find_by!(candidate:, employer:, job:)
    end
    render json: { id: conversation.id, conversation: { id: conversation.id } }, status: :created
  end

  # The counterpart is whichever side the viewer is not on; account role does not
  # decide it (a jobseeker who hires is the employer side of a conversation).
  def serialize(conversation)
    counterpart = conversation.counterpart_for(current_user)
    {
      id: conversation.id, candidateName: conversation.candidate.name, employerName: conversation.employer.name,
      counterpartId: counterpart.id, counterpartName: counterpart.name,
      viewerSide: conversation.candidate_id == current_user.id ? "candidate" : "employer",
      jobId: conversation.job_id, jobTitle: conversation.job&.title,
      lastMessage: conversation[:last_message_body], lastMessageAt: conversation[:last_message_at],
      lastMessageFromMe: conversation[:last_message_sender_id].present? && conversation[:last_message_sender_id] == current_user.id,
      unreadCount: conversation[:unread_count].to_i, updatedAt: conversation.updated_at
    }
  end

  def resolve_candidate
    id = params[:candidateId].presence || (current_user.jobseeker? ? current_user.id : nil)
    User.jobseeker.active.find_by(id:)
  end

  def resolve_employer(job)
    id = job&.employer_id || params[:employerId].presence || (params[:candidateId].present? ? current_user.id : nil)
    User.active.where.not(role: "admin").find_by(id:)
  end
end
