class ApplicationController < ActionController::API
  around_action :log_request
  before_action :require_verified_email_for_mutation
  rescue_from ActiveRecord::RecordNotFound, with: -> { render_error("Not found", :not_found) }
  rescue_from ActiveRecord::RecordInvalid, with: ->(error) { render_error(error.record.errors.full_messages.to_sentence, :unprocessable_entity) }

  private

  def log_request
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round(1)
    Rails.logger.info({
      event: "http_request", requestId: request.request_id, method: request.method,
      path: request.path, status: response.status, durationMs: duration_ms,
      userId: @current_user&.id
    }.compact.to_json)
  end

  def require_verified_email_for_mutation
    return if request.get? || request.head? || is_a?(AuthController)
    return unless ENV["REQUIRE_EMAIL_VERIFICATION"] == "true"
    return unless current_user && !current_user.admin? && !current_user.email_verified?

    render_error("Verify your email before making changes.", :forbidden, "EMAIL_NOT_VERIFIED")
  end

  def current_user
    return @current_user if defined?(@current_user)
    token = request.authorization.to_s.match(/^Bearer\s+(.+)$/i)&.captures&.first
    session = Session.active.find_by(token_digest: digest(token)) if token.present?
    @current_user = session&.user
  end

  def authenticate!(*roles)
    unless current_user
      render_error("Authentication required", :unauthorized)
      return false
    end
    unless current_user.active?
      render_error("This account is not active.", :forbidden, "ACCOUNT_INACTIVE")
      return false
    end
    if roles.any? && !roles.map(&:to_s).include?(current_user.role)
      render_error("You do not have permission to perform this action", :forbidden)
      return false
    end
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

  def public_employer(user)
    profile = user.profile
    {
      id: user.id,
      name: user.name,
      role: user.role,
      companyName: profile&.company_name,
      companyWebsite: profile&.company_website,
      companySize: profile&.company_size,
      companyDescription: profile&.company_description,
      headline: profile&.headline,
      location: profile&.location,
      website: profile&.website,
      verified: profile&.verified || false
    }
  end

  def audit!(action, entity = nil, metadata = {})
    AuditLog.create!(actor: current_user, action:, entity_type: entity&.class&.name, entity_id: entity&.id, metadata:)
  end

  def throttle!(bucket, limit:, period:)
    key = "rate:#{bucket}:#{request.remote_ip}:#{Time.current.to_i / period.to_i}"
    count = Rails.cache.increment(key, 1, expires_in: period) || 1
    return true if count <= limit
    render_too_many_requests
    false
  end

  # Failure-only throttling: callers check the budget before attempting an
  # action and spend it only when the attempt fails. Each scope is a
  # [identifier, limit] pair, e.g. { email: [address, 10], ip: [remote_ip, 50] }.
  # Identifiers are hashed so cache keys never contain email addresses.
  def failure_budget_exhausted?(bucket, scopes, period:)
    exhausted = scopes.any? do |scope, (identifier, limit)|
      next false if identifier.blank?
      # Incrementing by zero is an atomic read that works on every cache store.
      (Rails.cache.increment(failure_key(bucket, scope, identifier, period), 0, expires_in: period) || 0) >= limit
    end
    render_too_many_requests if exhausted
    exhausted
  end

  def record_failure!(bucket, scopes, period:)
    scopes.each do |scope, (identifier, _limit)|
      next if identifier.blank?
      Rails.cache.increment(failure_key(bucket, scope, identifier, period), 1, expires_in: period)
    end
  end

  def failure_key(bucket, scope, identifier, period)
    "rate:#{bucket}:#{scope}:#{digest(identifier)}:#{Time.current.to_i / period.to_i}"
  end

  def render_too_many_requests
    render_error("Too many requests. Try again later.", :too_many_requests)
  end
end
