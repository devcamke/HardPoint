require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # Local disk on one server; object storage once there are several (config/deploy.scaled.yml).
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint. HSTS covers every shop's subdomain.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } }, hsts: { subdomains: true, expires: 1.year } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "hardpoint.app"), protocol: "https" }

  # Shops live on subdomains of APP_HOST; raise the TLD length for hosts like hardpoint.co.ke.
  config.action_dispatch.tld_length = ENV.fetch("APP_TLD_LENGTH", 1).to_i

  # AWS SES through its SMTP interface. Create SMTP credentials in the SES console and add them
  # with bin/rails credentials:edit under ses: { smtp_username:, smtp_password:, region: }.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: "email-smtp.#{Rails.application.credentials.dig(:ses, :region) || "eu-west-1"}.amazonaws.com",
    port: 587,
    user_name: Rails.application.credentials.dig(:ses, :smtp_username),
    password: Rails.application.credentials.dig(:ses, :smtp_password),
    authentication: :login,
    enable_starttls: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [ ENV.fetch("APP_HOST", "hardpoint.app"), ".#{ENV.fetch("APP_HOST", "hardpoint.app")}" ]

  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Requests arrive through Cloudflare and kamal-proxy. Trusting Cloudflare's published ranges
  # makes request.remote_ip the visitor's address (for sign-in records and M-Pesa callback checks).
  config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20
    188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { IPAddr.new(_1) }

  # Safaricom's published callback addresses (check the Daraja portal for changes).
  config.x.mpesa_callback_ips = ENV.fetch("MPESA_CALLBACK_IPS", %w[
    196.201.214.200 196.201.214.206 196.201.213.114 196.201.214.207 196.201.214.208 196.201.213.44
    196.201.212.127 196.201.212.138 196.201.212.129 196.201.212.136 196.201.212.74 196.201.212.69
  ].join(",")).split(",").map { IPAddr.new(_1.strip) }
end
