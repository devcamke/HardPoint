require "net/smtp"

# An SMTP hiccup (an SES throttle, a timeout) shouldn't lose an email for good: a password reset,
# an invoice, or an owner's "your backup failed". Mail is tried again over about 20 minutes.
ActiveSupport.on_load(:action_mailer) do
  ActionMailer::MailDeliveryJob.retry_on Net::OpenTimeout, Net::ReadTimeout, Net::SMTPServerBusy, Net::SMTPUnknownError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, OpenSSL::SSL::SSLError,
    wait: :polynomially_longer, attempts: 5
end
