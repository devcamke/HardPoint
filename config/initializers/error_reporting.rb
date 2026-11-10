# Somebody is told when something breaks. Unhandled exceptions in requests and jobs, exhausted job retries,
# failed scheduled tasks and anything reported with Rails.error go to Sentry when SENTRY_DSN is set
# (config/initializers/sentry.rb). Without Sentry, they're emailed to the operators (ALERTS_EMAIL, or the
# support address): the first time straight away, then at most a daily reminder while the same error keeps
# happening, so a storm of one failure is one email.
# Platform checks (PlatformHealth) alert the same way, with or without Sentry. See docs/RUNBOOK.md, "Alerts".
Rails.application.configure do
  config.x.alerts = {
    email: ENV.fetch("ALERTS_EMAIL") { config.x.support[:email] },
    sentry: ENV["SENTRY_DSN"].present?
  }
end

Rails.application.config.after_initialize do
  if Rails.env.production? && !Rails.configuration.x.alerts[:sentry]
    Rails.error.subscribe(Alerts::ErrorSubscriber.new)
  end
end
