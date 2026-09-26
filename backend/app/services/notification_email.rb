# Content for notification emails (bookings, applications, messages). Rendering is
# kept separate from the token-link templates in EmailDelivery; the rendered email is
# handed to EmailDelivery.deliver_rendered, which owns the provider integrations.
#
# Every interpolated value is user-supplied (names, titles), so HTML is escaped and
# message bodies are never part of an email.
class NotificationEmail
  PRODUCTION_FRONTEND_URL = "https://verse-music-platform.vercel.app".freeze
  UNSUBSCRIBE_PURPOSE = :notification_email_unsubscribe

  TEMPLATES = {
    "booking_enquiry" => {
      subject: ->(p) { "New booking enquiry for #{p['act']}" },
      heading: ->(_) { "New booking enquiry" },
      copy: ->(p) { "#{p['name']} sent an enquiry for #{p['act']}. Review the brief and reply with a quote." },
      action: "View bookings", path: "/bookings"
    },
    "booking_status" => {
      subject: ->(p) { "Booking update: #{p['act']}" },
      heading: ->(_) { "Your booking was updated" },
      copy: ->(p) { "The booking for #{p['act']} is now #{p['status']}." },
      action: "View bookings", path: "/bookings"
    },
    "application_status" => {
      subject: ->(p) { "Application update: #{p['job']}" },
      heading: ->(_) { "Your application was updated" },
      copy: ->(p) { "Your application for #{p['job']} is now #{p['status']}." },
      action: "View applications", path: "/applications"
    },
    "new_message" => {
      subject: ->(p) { "New message from #{p['name']} on Verse" },
      heading: ->(_) { "You have a new message" },
      copy: ->(p) { p["job"].present? ? "#{p['name']} sent you a message about #{p['job']}." : "#{p['name']} sent you a message." },
      action: "Read and reply", path: "/messages"
    }
  }.freeze

  # Only verified addresses are emailed (an unverified address may not belong to the account
  # holder), and never to someone who turned notification emails off. Transactional emails
  # (sign-in codes, verification, password reset) do not go through this class.
  def self.deliverable_to?(user)
    EmailDelivery.configured? && user.email.present? && user.email_verified? && user.status == "active" && opted_in?(user)
  end

  # Users without a profile row (admins) keep the column default: opted in.
  def self.opted_in?(user) = user.profile.nil? || user.profile.email_notifications?

  # Returns { subject:, html:, text:, headers: }. Raises KeyError for an unknown template.
  def self.render(template, params, user)
    spec = TEMPLATES.fetch(template)
    params = params.to_h.stringify_keys
    link = "#{frontend_url}#{workspace(user)}#{params['path'].presence || spec[:path]}"
    subject = spec[:subject].call(params).squish.first(150)
    heading = spec[:heading].call(params)
    copy = spec[:copy].call(params)
    token = CGI.escape(unsubscribe_token(user))
    unsubscribe_page = "#{frontend_url}/unsubscribe?token=#{token}"
    {
      subject:, html: html(heading:, copy:, action: spec[:action], link:, unsubscribe: unsubscribe_page),
      text: "#{heading}\n\n#{copy}\n\n#{link}\n\nTurn off these emails: #{unsubscribe_page}",
      headers: unsubscribe_headers(token, unsubscribe_page)
    }
  end

  # Signed, purpose-scoped and non-expiring, so an old email's link keeps working. It can
  # only turn notification emails off for the user it names.
  def self.unsubscribe_token(user) = unsubscribe_verifier.generate(user.id, purpose: UNSUBSCRIBE_PURPOSE)

  def self.user_for_unsubscribe_token(token)
    id = unsubscribe_verifier.verified(token.to_s, purpose: UNSUBSCRIBE_PURPOSE)
    id.is_a?(String) ? User.find_by(id:) : nil
  rescue StandardError
    nil
  end

  def self.unsubscribe_verifier = Rails.application.message_verifier("notification-email-unsubscribe")

  # RFC 8058 one-click needs an HTTPS endpoint that accepts POST, i.e. the API (API_HOST).
  # Without API_HOST only the web page is advertised.
  def self.unsubscribe_headers(token, unsubscribe_page)
    api_host = ENV["API_HOST"].to_s.strip.sub(%r{/+\z}, "")
    return { "List-Unsubscribe" => "<#{unsubscribe_page}>" } if api_host.blank?

    { "List-Unsubscribe" => "<#{api_host}/api/notifications/unsubscribe?token=#{token}>", "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click" }
  end

  def self.workspace(user) = user.role == "employer" ? "/employer" : "/jobseeker"

  def self.frontend_url
    configured = ENV["FRONTEND_URL"].to_s.strip.sub(%r{/+\z}, "")
    return configured if configured.present?
    Rails.env.production? ? PRODUCTION_FRONTEND_URL : "http://localhost:5173"
  end

  def self.html(heading:, copy:, action:, link:, unsubscribe:)
    h = ERB::Util.method(:html_escape)
    <<~HTML.squish
      <!doctype html><html><body style="margin:0;background:#0b0b12;color:#f8fafc;font-family:Arial,sans-serif"><div style="max-width:560px;margin:0 auto;padding:40px 24px"><div style="font-size:22px;font-weight:800;color:#a78bfa">VERSE</div><h1 style="font-size:26px;margin:28px 0 12px">#{h.call(heading)}</h1><p style="color:#cbd5e1;line-height:1.6">#{h.call(copy)}</p><a href="#{h.call(link)}" style="display:inline-block;margin-top:18px;padding:13px 20px;border-radius:12px;background:#7c3aed;color:white;text-decoration:none;font-weight:700">#{h.call(action)}</a><p style="margin-top:28px;color:#94a3b8;font-size:13px">You are receiving this because of activity on your Verse account. <a href="#{h.call(unsubscribe)}" style="color:#a78bfa">Turn off these emails</a>.</p></div></body></html>
    HTML
  end

  private_class_method :html
end
