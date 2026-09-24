require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Hardpoint
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Row-level security policies can't be expressed in schema.rb.
    config.active_record.schema_format = :sql

    # Where Safaricom and KRA reach this app, for callback URLs.
    config.x.webhook_url_options = { host: ENV.fetch("APP_HOST", "localhost"), protocol: ENV["APP_HOST"] ? "https" : "http" }

    # Addresses M-Pesa callbacks may come from; empty accepts any (development and tests). Production
    # sets Safaricom's published addresses; override with MPESA_CALLBACK_IPS (comma-separated).
    config.x.mpesa_callback_ips = []

    # Names this release (Kamal sets KAMAL_VERSION on deploy); a new one refreshes tills' offline copies.
    config.x.release = ENV.fetch("KAMAL_VERSION") { Time.now.utc.strftime("%Y%m%d%H%M%S") }

    # Texts go to Africa's Talking only in production; elsewhere they're kept in Sms::Outbox.
    config.x.sms_outbox = !Rails.env.production?

    # How shops reach HardPoint: the support inbox (support requests are emailed here) and a WhatsApp
    # number in international format without the plus.
    # Webhooks may only be sent to public addresses; development and tests use local receivers.
    config.x.webhooks_allow_private_addresses = !Rails.env.production?

    config.x.support = {
      email: ENV.fetch("SUPPORT_EMAIL", "support@hardpoint.app"),
      whatsapp: ENV.fetch("SUPPORT_WHATSAPP", "254700000000")
    }
  end
end
