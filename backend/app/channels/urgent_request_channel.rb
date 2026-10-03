# An urgent request's status, matching progress and responses, for the hirer who posted it.
class UrgentRequestChannel < ApplicationCable::Channel
  def subscribed
    request = UrgentRequest.find_by(id: params[:id])
    return reject unless request && request.requester_id == current_user.id
    stream_for request
  end
end
