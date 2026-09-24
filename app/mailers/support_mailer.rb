# Support requests, to HardPoint's support inbox; replying goes straight to the person who asked.
class SupportMailer < ApplicationMailer
  def received
    @support_request = params[:support_request]
    @account, @user = @support_request.account, @support_request.user
    mail to: Rails.configuration.x.support[:email], reply_to: @user.email_address,
      subject: "[#{@support_request.reference}] #{@account.name}: #{@support_request.subject}"
  end
end
