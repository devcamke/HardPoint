# Tells the operators that something needs them, by email (ALERTS_EMAIL). The first time something goes wrong
# the email goes straight away; while it carries on, at most one "still happening" reminder a day, with how
# many times it has happened since; and when a check that was failing passes again, an "all clear". Sent
# straight away rather than through the job queue, because the queue being down is one of the things worth
# hearing about.
#
# An alert is over when it's resolved, or when nothing has been reported for it for QUIET_FOR, so an error
# that comes back a week later is news again.
module Alerts
  REMIND_EVERY = 1.day
  QUIET_FOR = 1.day

  # key: what this alert is about ("health:queue", "error:NoMethodError:3f9a…"); reminders are per key.
  # Returns true if an email went out, false if it was held back as a repeat.
  def self.notify(key, subject, body)
    if Rails.cache.write(state_key(key), { since: Time.current.to_i, count: 1 }, unless_exist: true, expires_in: QUIET_FOR)
      Rails.cache.write(reminder_key(key), true, expires_in: REMIND_EVERY)
      deliver subject, body
    else
      # Read and written back rather than counted atomically: the count in a reminder is a guide, not a ledger.
      state = Rails.cache.read(state_key(key)) || { since: Time.current.to_i, count: 0 }
      state = state.merge(count: state[:count] + 1)
      Rails.cache.write(state_key(key), state, expires_in: QUIET_FOR)
      return false unless Rails.cache.write(reminder_key(key), true, unless_exist: true, expires_in: REMIND_EVERY)

      deliver "Still happening: #{subject}", "#{state[:count]} times since #{format_time(state[:since])}. The latest:\n\n#{body}"
    end
  rescue => error
    # Alerting must never make the problem worse. The error goes to the log, which is shipped off the server.
    Rails.logger.error "Alerts: couldn't send #{key.inspect}: #{error.class}: #{error.message}"
    false
  end

  # The thing behind `key` is fine again. Emails an all clear if an alert for it was sent; returns whether one was.
  def self.resolve(key, subject)
    state = Rails.cache.read(state_key(key)) or return false
    return false unless Rails.cache.delete(state_key(key))

    Rails.cache.delete(reminder_key(key))
    deliver "All clear: #{subject}", "Passing again. It was failing from #{format_time(state[:since])}, reported #{state[:count]} times."
  rescue => error
    Rails.logger.error "Alerts: couldn't send the all clear for #{key.inspect}: #{error.class}: #{error.message}"
    false
  end

  def self.email = Rails.configuration.x.alerts[:email]

  def self.deliver(subject, body)
    OperationsMailer.with(subject: subject, body: body).alert.deliver_now
    true
  end
  private_class_method :deliver

  def self.format_time(unix) = Time.zone.at(unix).utc.strftime("%-d %b %H:%M UTC")
  def self.state_key(key) = "alerts:#{key}"
  def self.reminder_key(key) = "alerts:#{key}:reminded"
  private_class_method :format_time, :state_key, :reminder_key
end
