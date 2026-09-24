require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module VerseApi
  class Application < Rails::Application
    config.load_defaults 7.2
    config.api_only = true
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
