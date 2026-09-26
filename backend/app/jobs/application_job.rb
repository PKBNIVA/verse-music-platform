class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  # Runs once when a job is given up on: discarded, retries exhausted, or an unhandled error
  # (GoodJob does not retry those: retry_on_unhandled_error = false).
  after_discard { |job, error| ErrorReporter.capture_job_failure(job, error) }
end
