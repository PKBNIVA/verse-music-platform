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
  config.active_job.queue_adapter = :good_job
  # db/schema.rb is committed; never let a migration inside the container rewrite it.
  config.active_record.dump_schema_after_migration = false
  config.cache_store = ENV["REDIS_URL"].present? ? [:redis_cache_store, { url: ENV["REDIS_URL"], connect_timeout: 2, read_timeout: 1, write_timeout: 1 }] : :memory_store
end
