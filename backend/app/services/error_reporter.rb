# Thin wrapper around the error tracker for errors the app rescues and handles itself
# (a swallowed email failure, a reconciliation error, a discarded job). Without a
# configured Sentry DSN every method is a no-op, and reporting can never raise into
# the caller: behaviour stays identical to the plain Rails.logger call it sits next to.
module ErrorReporter
  module_function

  def enabled?
    defined?(Sentry) && Sentry.initialized?
  end

  # Returns the captured Sentry event, or nil when disabled/filtered.
  # `tags` are short searchable strings; other keyword context goes to extras. Both are scrubbed.
  def capture(exception, tags: {}, level: :error, **context)
    return nil unless enabled?

    Sentry.with_scope do |scope|
      scope.set_level(level)
      scope.set_tags(ErrorScrubber.scrub(tags.transform_values(&:to_s)))
      scope.set_extras(ErrorScrubber.scrub(context)) if context.any?
      Sentry.capture_exception(exception)
    end
  rescue StandardError => error
    Rails.logger.warn({ event: "error_report_failed", error: error.class.name }.to_json)
    nil
  end

  # A background job gave up (discarded, retries exhausted or unhandled). Only the class
  # and id are sent: job arguments can hold encrypted tokens or email addresses.
  def capture_job_failure(job, exception)
    capture(exception, tags: { source: "active_job", job_class: job.class.name, job_id: job.job_id }, job_class: job.class.name, job_id: job.job_id)
  end

  # Identifies the signed-in user on the current request's scope: internal id and role only.
  def set_user(user)
    return unless enabled? && user

    Sentry.set_user(id: user.id, role: user.role)
  rescue StandardError
    nil
  end
end
