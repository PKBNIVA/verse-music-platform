require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module VerseApi
  class Application < Rails::Application
    config.load_defaults 7.2
    config.api_only = true
    config.autoload_lib(ignore: %w[assets tasks])
    config.active_job.queue_adapter = :async
    config.action_dispatch.cookies_same_site_protection = :none
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
      key: "verse_session",
      secure: Rails.env.production?,
      httponly: true,
      same_site: Rails.env.production? ? :none : :lax
  end
end
