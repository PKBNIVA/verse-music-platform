# Removes personal data and credentials from everything sent to the error tracker.
#
# Applied as Sentry's before_send (see config/initializers/sentry.rb) and to the context
# ErrorReporter attaches. It is deliberately aggressive: an over-filtered report is still
# useful, a leaked token or email address is not.
module ErrorScrubber
  FILTERED = "[Filtered]".freeze
  EMAIL_PLACEHOLDER = "[email]".freeze
  MAX_DEPTH = 8

  # Hash keys whose values are never sent. Matched against the key name.
  SENSITIVE_KEY = /pass(word|wd)?|token|secret|signature|otp|authorization|cookie|api[_-]?key|access[_-]?key|private[_-]?key|credential|session|email|\A(code|body|dsn)\z/i
  EMAIL = /[A-Za-z0-9._%+\-]+(?:@|%40)[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/i
  AUTH_SCHEME = /\b(Bearer|Basic|Token)\s+[A-Za-z0-9\-._~+\/=]+/i
  # ?token=…, &reset_token=…, &code=…, &signature=… etc. in URLs and query strings.
  QUERY_SECRET = /((?:\A|[?&;\s"'])[\w\-\[\]]*(?:token|code|otp|secret|signature|password|email|key)[\w\-\[\]]*=)[^&#\s"'<>]*/i
  REQUEST_ENV_ALLOWED = %w[SERVER_NAME SERVER_PORT].freeze

  module_function

  def before_send(event, _hint = nil)
    scrub_event!(event)
    event
  end

  def scrub_event!(event)
    event.message = scrub_string(event.message) if event.message.is_a?(String)
    event.transaction = scrub_string(event.transaction) if event.transaction.is_a?(String)
    event.extra = scrub(event.extra || {})
    event.tags = scrub(event.tags || {})
    event.contexts = scrub(event.contexts || {})
    event.user = scrub_user(event.user)
    scrub_request!(event.request) if event.request
    if event.respond_to?(:exception) && event.exception
      event.exception.values.each do |value|
        value.value = scrub_string(value.value) if value.value.is_a?(String)
        scrub_frames!(value.stacktrace&.frames)
      end
    end
    scrub_breadcrumbs!(event.breadcrumbs)
    event
  end

  # Anything nested: hashes lose sensitive keys, strings lose emails/tokens.
  def scrub(value, depth = 0)
    return FILTERED if depth > MAX_DEPTH

    case value
    when Hash
      value.each_with_object({}) do |(key, item), clean|
        clean[key] = sensitive_key?(key) ? FILTERED : scrub(item, depth + 1)
      end
    when Array then value.map { scrub(_1, depth + 1) }
    when String then scrub_string(value)
    when Symbol then scrub_string(value.to_s).to_sym
    else value
    end
  end

  def scrub_string(value)
    return value unless value.is_a?(String)

    value
      .gsub(AUTH_SCHEME) { "#{Regexp.last_match(1)} #{FILTERED}" }
      .gsub(QUERY_SECRET) { "#{Regexp.last_match(1)}#{FILTERED}" }
      .gsub(EMAIL, EMAIL_PLACEHOLDER)
  end

  def scrub_query(query)
    return query if query.blank?

    scrub_string("?#{query}").delete_prefix("?")
  end

  def sensitive_key?(key)
    key.to_s.match?(SENSITIVE_KEY)
  end

  # Only the internal id and role ever identify a user.
  def scrub_user(user)
    return {} unless user.is_a?(Hash)

    user.transform_keys(&:to_sym).slice(:id, :role)
  end

  def scrub_request!(request)
    request.url = scrub_string(request.url) if request.url
    request.query_string = scrub_query(request.query_string) if request.query_string
    request.headers = scrub(request.headers || {})
    request.cookies = nil
    request.data = nil
    request.env = (request.env || {}).slice(*REQUEST_ENV_ALLOWED)
  end

  # Source context lines and (if ever enabled) local variables.
  def scrub_frames!(frames)
    Array(frames).each do |frame|
      frame.context_line = scrub_string(frame.context_line) if frame.context_line.is_a?(String)
      frame.pre_context = scrub(frame.pre_context) if frame.pre_context
      frame.post_context = scrub(frame.post_context) if frame.post_context
      frame.vars = scrub(frame.vars) if frame.vars
    end
  end

  def scrub_breadcrumbs!(breadcrumbs)
    return unless breadcrumbs.respond_to?(:each)

    breadcrumbs.each do |crumb|
      crumb.message = scrub_string(crumb.message) if crumb.message.is_a?(String)
      crumb.data = scrub(crumb.data) if crumb.data
    end
  end
end
