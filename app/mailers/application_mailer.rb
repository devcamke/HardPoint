class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "HardPoint <no-reply@hardpoint.co.ke>")
  layout "mailer"
end
