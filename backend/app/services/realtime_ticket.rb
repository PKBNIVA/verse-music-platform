# Short-lived, single-use signed tickets that let a browser open the Action Cable socket (see
# ApplicationCable::Connection). A ticket names a session, not a user, so signing out or an expired
# session also invalidates tickets already handed out. It travels as a WebSocket subprotocol
# (PROTOCOL_PREFIX + ticket), never in the URL, so it is not written to request logs.
module RealtimeTicket
  PURPOSE = :cable
  PROTOCOL_PREFIX = "musilynk.ticket.".freeze

  module_function

  def ttl = Integer(settings.fetch("ticket_ttl_seconds")).seconds
  def tickets_per_minute = Integer(settings.fetch("tickets_per_minute"))

  def issue(session) = verifier.generate({ "s" => session.id, "j" => SecureRandom.uuid }, expires_in: ttl, purpose: PURPOSE)

  # The ticket from the socket's Sec-WebSocket-Protocol header, or nil.
  def from_protocols(header)
    header.to_s.split(",").map(&:strip).find { _1.start_with?(PROTOCOL_PREFIX) }&.delete_prefix(PROTOCOL_PREFIX)
  end

  # The active session the ticket names, or nil. A ticket works once: its one-time id is recorded
  # in the shared cache until it would have expired anyway.
  def session_for(ticket)
    return nil if ticket.blank? || !ticket.is_a?(String)
    payload = verifier.verified(ticket, purpose: PURPOSE)
    return nil unless payload.is_a?(Hash) && payload["s"] && payload["j"]
    return nil unless Rails.cache.write("realtime-ticket/#{payload['j']}", true, expires_in: ttl, unless_exist: true)
    session = Session.active.find_by(id: payload["s"])
    session if session && session.expires_at > Time.current && session.user&.active?
  end

  def user_for(ticket) = session_for(ticket)&.user

  # URL-safe, so the ticket is a valid subprotocol token.
  def verifier = @verifier ||= ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("realtime-ticket"), url_safe: true)

  def settings
    @settings ||= YAML.safe_load_file(Rails.root.join("config/realtime.yml")).freeze
  end
end
