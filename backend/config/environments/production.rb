Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.assume_ssl = true
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.active_storage.service = ENV["AWS_BUCKET"].present? ? :amazon : :local
  config.action_mailer.default_url_options = { host: ENV.fetch("FRONTEND_HOST", "localhost") }
end
