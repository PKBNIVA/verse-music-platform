require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module VerseApi
  class Application < Rails::Application
    config.load_defaults 7.2
    # Rails 8.0 default, adopted early (see config/initializers/new_framework_defaults_8_0.rb).
    # Must live here: ActiveSupport reads it before config/initializers load.
    config.active_support.to_time_preserves_timezone = :zone
    config.api_only = true
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
