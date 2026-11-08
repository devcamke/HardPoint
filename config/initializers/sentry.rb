# Error and performance reporting to Sentry, only when a project's DSN is set (SENTRY_DSN). Without one,
# nothing is sent anywhere and config/initializers/error_reporting.rb emails the operators instead.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = Rails.configuration.x.environment_name
    config.release = Rails.configuration.x.release
    config.breadcrumbs_logger = %i[ active_support_logger http_logger ]
    # Shops' data stays here: no request bodies, cookies or addresses go with an error. Rails' parameter
    # filter (passwords, PINs, phone numbers…) applies to what is sent.
    config.send_default_pii = false
    config.excluded_exceptions += %w[ ActionController::RoutingError ActiveRecord::RecordNotFound ActionController::InvalidAuthenticityToken ]
    # A sample of requests and jobs for performance; raise it when looking into slowness.
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.05).to_f
  end
end
