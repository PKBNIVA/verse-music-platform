class MessagesController < ApplicationController
  before_action -> { authenticate! }
  def index
    conversation = Conversation.find(params[:conversation_id]); return render_error("Conversation not found", :not_found) unless conversation.includes_user?(current_user)
    conversation.messages.where.not(sender: current_user).where(read_at: nil).update_all(read_at: Time.current)
    render json: { messages: conversation.messages.order(created_at: :asc).map { serialize(_1) } }
  end
  def create
    conversation = Conversation.find(params[:conversation_id]); return render_error("Conversation not found", :not_found) unless conversation.includes_user?(current_user)
    message = conversation.messages.create!(sender: current_user, body: params[:body].to_s.strip.first(5000))
    render json: { message: serialize(message) }, status: :created
  end
  private
  def serialize(message) = { id: message.id, senderId: message.sender_id, body: message.body, createdAt: message.created_at, readAt: message.read_at }
end
