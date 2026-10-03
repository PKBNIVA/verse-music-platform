module ApplicationCable
  # A socket is opened with a ticket from POST /api/cable/ticket (RealtimeTicket), sent as a
  # WebSocket subprotocol: browsers cannot send the bearer token, and a URL would be logged. The
  # session is checked again here, so a signed-out or expired session cannot connect with an old
  # ticket, and a ticket works once. Identified by user and session, so revoking a session closes
  # its sockets (Realtime.disconnect).
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session

    def connect
      session = RealtimeTicket.session_for(RealtimeTicket.from_protocols(request.headers["Sec-WebSocket-Protocol"]))
      reject_unauthorized_connection unless session
      self.current_session = session
      self.current_user = session.user
    end
  end
end
