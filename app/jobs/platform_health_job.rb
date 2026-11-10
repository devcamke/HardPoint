# Every ten minutes: run the platform checks and tell the operators about anything failing (Alerts sends the
# first failure straight away, then a daily reminder while it lasts), and send an all clear for a check that
# was failing and now isn't. The uptime monitor watching /health sees the same checks from outside.
class PlatformHealthJob < ApplicationJob
  def perform
    health = PlatformHealth.check
    health.checks.each do |check|
      key, name = "health:#{check.name}", check.name.to_s.humanize
      next Alerts.resolve(key, "#{name} check") unless check.failing?

      Alerts.notify key, "#{name} check failing: #{check.detail.truncate(80)}",
        "#{name}: #{check.detail}\n\nAll checks:\n#{health.checks.map { "  #{_1.status.to_s.ljust(8)} #{_1.name}: #{_1.detail}" }.join("\n")}"
    end
  end
end
