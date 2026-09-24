class WebhooksMailer < ApplicationMailer
  def disabled
    @endpoint = params[:endpoint]
    @account = @endpoint.account
    mail to: @account.billing_recipients, subject: "A webhook for #{@account.name} was switched off after repeated failures"
  end
end
