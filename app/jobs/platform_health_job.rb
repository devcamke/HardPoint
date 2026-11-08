# Every ten minutes: run the platform checks and tell the operators about anything failing (Alerts throttles
# to one email an hour per check). The uptime monitor watching /health sees the same checks from outside.
class PlatformHealthJob < ApplicationJob
  def perform
    health = PlatformHealth.check
    health.failing.each do |check|
      Alerts.notify "health:#{check.name}", "#{check.name.to_s.humanize} check failing: #{check.detail.truncate(80)}",
        "#{check.name.to_s.humanize}: #{check.detail}\n\nAll checks:\n#{health.checks.map { "  #{_1.status.to_s.ljust(8)} #{_1.name}: #{_1.detail}" }.join("\n")}"
    end
  end
end
