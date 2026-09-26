class ApplicationController < ActionController::API
  around_action :log_request
  before_action :require_verified_email_for_mutation
  rescue_from ActiveRecord::RecordNotFound, with: -> { render_error("Not found", :not_found) }
  rescue_from ActiveRecord::RecordInvalid, with: ->(error) { render_error(error.record.errors.full_messages.to_sentence, :unprocessable_entity, "VALIDATION_FAILED") }
  # Client mistakes that would otherwise surface as 500s (or as framework error pages without
  # the {error, code} shape). Later declarations take precedence over earlier ones.
  rescue_from ArgumentError, with: :render_invalid_argument
  rescue_from ActiveModel::RangeError, with: -> { render_error("A number is outside the allowed range.", :unprocessable_entity, "OUT_OF_RANGE") }
  rescue_from ActiveRecord::NotNullViolation, with: :render_missing_column
  rescue_from ActiveRecord::RecordNotUnique, with: -> { render_error("This record already exists.", :conflict, "CONFLICT") }
  rescue_from ActionController::BadRequest, with: ->(error) { render_error(error.message.presence || "Bad request", :bad_request, "BAD_REQUEST") }
  rescue_from ActionController::ParameterMissing, with: ->(error) { render_error("Missing parameter: #{error.param}", :bad_request, "PARAMETER_MISSING") }
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: -> { render_error("Request body is not valid JSON.", :bad_request, "MALFORMED_JSON") }

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

  # Enum assignment ("'x' is not a valid status") and PostgreSQL's refusal of NUL bytes are
  # input errors; any other ArgumentError is a programming error and stays a 500.
  INVALID_ARGUMENT_PATTERN = /is not a valid \w+|string contains null byte/

  def render_invalid_argument(error)
    raise error unless error.message.match?(INVALID_ARGUMENT_PATTERN)
    message = error.message.include?("null byte") ? "Text may not contain NUL characters." : error.message.delete("'").capitalize
    render_error(message, :unprocessable_entity, "INVALID_VALUE")
  end

  # A NOT NULL column reached the database without a value: a required field was omitted.
  def render_missing_column(error)
    column = error.cause.respond_to?(:result) ? error.cause.result&.error_field(PG::Result::PG_DIAG_COLUMN_NAME) : nil
    field = column.to_s.camelize(:lower).presence
    render_error(field ? "#{field} is required." : "A required field is missing.", :unprocessable_entity, "MISSING_FIELD")
  end

  def digest(value)
    Digest::SHA256.hexdigest(value.to_s)
  end

  def public_user(user)
    user.as_json(except: %i[password_digest created_at updated_at], methods: %i[profileComplete emailVerified])
      .merge(user.profile&.api_json || {})
  end

  def public_profile(user)
    public_user(user).except("email", "status", "profileComplete", "emailVerified", "last_login_at", "phone", "synthetic_batch")
      .merge("demo" => SyntheticQa::Demo.user?(user))
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
