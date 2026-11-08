class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "HardPoint <no-reply@hardpoint.app>")
  layout "mailer"

  # Which mailer and email this is, for SES's per-kind statistics (Ses::Delivery tags the message with it).
  before_action { headers["X-HardPoint-Mailer"] = "#{self.class.name.delete_suffix("Mailer")}_#{action_name}" }
end
