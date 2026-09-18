class ApplicationController < ActionController::API
  include ActionController::Cookies

  rescue_from ActiveRecord::RecordNotFound, with: -> { render_error("Not found", :not_found) }
  rescue_from ActiveRecord::RecordInvalid, with: ->(error) { render_error(error.record.errors.full_messages.to_sentence, :unprocessable_entity) }

  private

  def current_user
    return @current_user if defined?(@current_user)
    token = request.authorization.to_s.match(/^Bearer\s+(.+)$/i)&.captures&.first || cookies.encrypted[:verse_session]
    session = Session.active.find_by(token_digest: digest(token)) if token.present?
    @current_user = session&.user
  end

  def authenticate!(*roles)
    return render_error("Authentication required", :unauthorized) unless current_user
    return render_error("This account is not active.", :forbidden, "ACCOUNT_INACTIVE") unless current_user.active?
    return render_error("You do not have permission to perform this action", :forbidden) if roles.any? && !roles.map(&:to_s).include?(current_user.role)
    true
  end

  def render_error(message, status, code = nil)
    render json: { error: message, code: code }.compact, status: status
  end

  def digest(value)
    Digest::SHA256.hexdigest(value.to_s)
  end

  def public_user(user)
    user.as_json(except: %i[password_digest created_at updated_at], methods: %i[profileComplete emailVerified])
      .merge(user.profile&.api_json || {})
  end

  def public_profile(user)
    public_user(user).except("email", "status", "profileComplete", "emailVerified", "last_login_at", "phone")
  end

  def audit!(action, entity = nil, metadata = {})
    AuditLog.create!(actor: current_user, action:, entity_type: entity&.class&.name, entity_id: entity&.id, metadata:)
  end

  def throttle!(bucket, limit:, period:)
    key = "rate:#{bucket}:#{request.remote_ip}:#{Time.current.to_i / period.to_i}"
    count = Rails.cache.increment(key, 1, expires_in: period) || 1
    return true if count <= limit
    render_error("Too many requests. Try again later.", :too_many_requests)
    false
  end
end
