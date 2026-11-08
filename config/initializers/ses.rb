# Email delivery through AWS SES (app/models/ses.rb): the :ses delivery method for the API, the interceptor that
# keeps bounced and complaining addresses out of every email, and the SES errors worth retrying a delivery on.
require "aws-sdk-sesv2"
require "aws-sdk-sns"

ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :ses, Ses::Delivery
  register_interceptor EmailSuppression::Interceptor

  # Throttling and SES's own hiccups are tried again with the SMTP ones (config/initializers/mail_delivery_retries.rb);
  # a message SES refuses outright (a bad address, sending paused) isn't.
  ActionMailer::MailDeliveryJob.retry_on Aws::SESV2::Errors::TooManyRequestsException, Aws::SESV2::Errors::ServiceUnavailableException,
    Aws::SESV2::Errors::InternalServiceErrorException, Seahorse::Client::NetworkingError, wait: :polynomially_longer, attempts: 5
end
