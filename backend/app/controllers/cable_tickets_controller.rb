# POST /api/cable/ticket: a short-lived ticket for opening the real-time socket (RealtimeTicket).
# Signed-in users only, rate-limited per user and IP.
class CableTicketsController < ApplicationController
  def create
    return unless authenticate!
    return render_error("Live updates are off.", :service_unavailable, "REALTIME_DISABLED") unless Realtime.enabled?
    return unless throttle!("cable-ticket:#{current_user.id}", limit: RealtimeTicket.tickets_per_minute, period: 1.minute)
    render json: { ticket: RealtimeTicket.issue(@current_session), expiresIn: RealtimeTicket.ttl.to_i, url: cable_url }, status: :created
  end

  private

  # The socket lives on this API host: wss:// behind TLS, ws:// locally.
  def cable_url = "#{request.ssl? ? 'wss' : 'ws'}://#{request.host_with_port}#{ActionCable.server.config.mount_path}"
end
