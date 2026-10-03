# One conversation's new messages, for its two participants only, and not while either has
# blocked the other ({ type: "message", id }).
class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:id])
    return reject unless conversation&.includes_user?(current_user)
    return reject if UserBlock.between?(conversation.candidate, conversation.employer)
    stream_for conversation
  end
end
