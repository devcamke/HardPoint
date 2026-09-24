class AccountClosuresMailer < ApplicationMailer
  def scheduled
    @account = params[:account]
    mail to: @account.billing_recipients, subject: "#{@account.name} will be deleted on #{@account.deletion_scheduled_for.to_date.to_fs(:long)}"
  end
end
