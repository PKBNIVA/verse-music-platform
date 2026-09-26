Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.active_storage.service = :test
  config.active_job.queue_adapter = :test
  # Rate-limit counters must not persist between runs (the default FileStore
  # writes to tmp/cache); throttling tests install their own MemoryStore.
  config.cache_store = :null_store
  # Surface framework deprecations as test failures so the next Rails upgrade has no
  # hidden work. Implicit `Model.connection` checkout is flagged too (use
  # `lease_connection` or `with_connection`).
  config.active_support.deprecation = :raise
  config.active_record.permanent_connection_checkout = :deprecated
end
