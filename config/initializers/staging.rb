# Staging (config/deploy.staging.yml) runs with RAILS_ENV=production and HARDPOINT_ENVIRONMENT=staging, on a
# scrambled copy of production's data. It must never reach real people: every email goes to the operators
# instead, texts stay in the outbox, and search engines are told to stay away. The banner at the top of every
# page says which one you're looking at.
Rails.application.configure do
  config.x.environment_name = ENV.fetch("HARDPOINT_ENVIRONMENT") { Rails.env }
  config.x.staging = config.x.environment_name == "staging"

  if config.x.staging
    config.x.sms_outbox = true
    config.action_dispatch.default_headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end

# Redirects every email staging would send to one inbox, with the real recipients in the subject.
class StagingMailInterceptor
  def self.delivering_email(mail)
    recipients = [ *mail.to, *mail.cc, *mail.bcc ].compact.uniq
    mail.subject = "[staging, for #{recipients.join(", ")}] #{mail.subject}"
    mail.to = ENV.fetch("STAGING_MAIL_TO") { Rails.configuration.x.support[:email] }
    mail.cc = mail.bcc = nil
  end
end

Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(StagingMailInterceptor) if Rails.configuration.x.staging
end
