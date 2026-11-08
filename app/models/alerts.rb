# Tells the operators that something needs them, by email (ALERTS_EMAIL), at most once an hour for the
# same thing: a repeating failure makes one email, not one a minute. Sent straight away rather than through
# the job queue, because the queue being down is one of the things worth hearing about.
module Alerts
  THROTTLE = 1.hour

  # key: what this alert is about ("health:queue", "error:NoMethodError:3f9a…"); the throttle is per key.
  # Returns true if an email went out, false if the same alert was sent within the last hour.
  def self.notify(key, subject, body)
    return false unless Rails.cache.write("alerts:#{key}", Time.current.to_i, unless_exist: true, expires_in: THROTTLE)

    OperationsMailer.with(subject: subject, body: body).alert.deliver_now
    true
  rescue => error
    # Alerting must never make the problem worse. The error goes to the log, which is shipped off the server.
    Rails.logger.error "Alerts: couldn't send #{key.inspect}: #{error.class}: #{error.message}"
    false
  end

  def self.email = Rails.configuration.x.alerts[:email]
end
