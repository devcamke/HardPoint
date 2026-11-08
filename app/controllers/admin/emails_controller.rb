# How email is doing: the SES account (may it send, sandbox or not, reputation, quota), the sending domain's
# verification and DKIM, and the addresses HardPoint has stopped writing to, each of which can be lifted.
class Admin::EmailsController < Admin::BaseController
  def show
    @configured = Ses.configured?
    @domain = Ses.sending_domain
    if Ses.api?
      @account = Ses.account
      @identity = Ses.client.get_email_identity(email_identity: @domain)
    end
    @suppressions = EmailSuppression.newest_first.limit(200).to_a
  rescue Aws::Errors::ServiceError => error
    @error = error.message
    @suppressions = EmailSuppression.newest_first.limit(200).to_a
  end
end
