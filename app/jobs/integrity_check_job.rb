# Nightly: run the integrity checks across every shop, keep the outcome for the admin page and the platform
# checks, and tell the operators about anything found (Alerts throttles to one email an hour per run-day).
class IntegrityCheckJob < ApplicationJob
  def perform
    check = IntegrityCheck.run
    check.remember!
    return if check.clean?

    Alerts.notify "integrity:#{Date.current}", "Data integrity: #{check.findings.size} #{"finding".pluralize(check.findings.size)} across #{check.findings.map(&:account_id).uniq.size} #{"shop".pluralize(check.findings.map(&:account_id).uniq.size)}",
      "The nightly integrity checks found:\n\n#{check.summary}\n\nEach is a bug or tampering until shown otherwise. The admin Database page has the same list; Activity in the shop shows who changed what."
  end
end
