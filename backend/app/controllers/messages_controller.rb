class MessagesController < ApplicationController
  include UserRateLimit

  HISTORY_LIMIT = 200
  SEND_LIMIT_PER_HOUR = 120
  MAX_LENGTH = 5_000

  before_action -> { authenticate! }
  before_action :load_conversation

  # Opening (or polling) a conversation marks the counterpart's messages and the
  # matching message notification as read.
  def index
    now = Time.current
    @conversation.messages.where.not(sender: current_user).where(read_at: nil).update_all(read_at: now, updated_at: now)
    Notifier.conversation_read(@conversation, current_user)
    # Most recent HISTORY_LIMIT messages, returned oldest-first.
    recent = @conversation.messages.order(created_at: :desc, id: :desc).limit(HISTORY_LIMIT + 1).to_a
    truncated = recent.size > HISTORY_LIMIT
    render json: { messages: recent.first(HISTORY_LIMIT).reverse.map { serialize(_1) }, truncated:, limit: HISTORY_LIMIT }
  end

  def create
    body = params[:body].to_s.strip
    return render_error("Write a message before sending.", :unprocessable_content, "MESSAGE_EMPTY") if body.empty?
    if body.length > MAX_LENGTH
      return render_error("Messages can be at most #{MAX_LENGTH} characters.", :unprocessable_content, "MESSAGE_TOO_LONG")
    end
    return unless within_user_rate_limit?("message", limit: SEND_LIMIT_PER_HOUR, period: 1.hour)

    message = Message.transaction do
      @conversation.messages.create!(sender: current_user, body:).tap { Notifier.new_message(_1) }
    end
    render json: { message: serialize(message) }, status: :created
  end

  private

  def load_conversation
    @conversation = Conversation.find_by(id: params[:conversation_id])
    render_error("Conversation not found", :not_found) unless @conversation&.includes_user?(current_user)
  end

  def serialize(message) = { id: message.id, senderId: message.sender_id, body: message.body, createdAt: message.created_at, readAt: message.read_at }
end
