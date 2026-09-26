Rails.application.configure do
  config.good_job.execution_mode = ENV.fetch("GOOD_JOB_EXECUTION_MODE", Rails.env.production? ? "async" : "external").to_sym
  config.good_job.max_threads = ENV.fetch("GOOD_JOB_MAX_THREADS", "2").to_i
  config.good_job.poll_interval = ENV.fetch("GOOD_JOB_POLL_INTERVAL", "10").to_i
  config.good_job.enable_cron = ENV.fetch("GOOD_JOB_ENABLE_CRON", Rails.env.production?.to_s) == "true"
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = false
  config.good_job.cron = {
    job_alert_sweep: {
      cron: "*/15 * * * *",
      class: "JobAlertSweepJob",
      description: "Deliver due daily and weekly job alerts"
    },
    auth_cleanup: {
      cron: "17 3 * * *",
      class: "AuthCleanupJob",
      description: "Delete expired sessions and email tokens expired or used more than 7 days ago"
    }
  }
end
