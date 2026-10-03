require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module MusilynkApi
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    # Uploads are served as-is; nothing generates image variants, so no image_processing/libvips.
    config.active_storage.variant_processor = :disabled
    config.autoload_lib(ignore: %w[assets tasks])
    # Relations marked strict_loading (the inbox, bookings and thread lists) must not lazy-load an
    # association: development and tests raise so the missing preload is fixed; production only logs,
    # so an unforeseen path costs a query rather than a failed request.
    config.active_record.action_on_strict_loading_violation = Rails.env.production? ? :log : :raise

    # Real-time updates (Action Cable at /cable; channels in app/channels, config/realtime.yml).
    # Sockets are accepted from the same origins as the API's CORS (ALLOWED_ORIGINS and
    # ADMIN_ORIGIN), read per connection like the CORS initializer does.
    realtime = YAML.safe_load_file(Rails.root.join("config/realtime.yml"))
    config.action_cable.mount_path = "/cable"
    config.action_cable.worker_pool_size = Integer(realtime.fetch("worker_pool_size"))
    config.action_cable.allowed_request_origins = [
      lambda do |origin|
        origins = ENV.fetch("ALLOWED_ORIGINS", "http://localhost:5173").split(",").map(&:strip)
        origins << ENV["ADMIN_ORIGIN"].to_s.strip if ENV["ADMIN_ORIGIN"].present?
        origins.include?(origin)
      end
    ]
  end
end
