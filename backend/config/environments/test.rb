Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.active_storage.service = :test
  config.active_job.queue_adapter = :test
end
