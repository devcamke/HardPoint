class AccountExportsMailer < ApplicationMailer
  def ready
    @export = params[:export]
    @account = @export.account
    mail to: @export.requested_by.email_address, subject: "Your #{@account.name} data export is ready"
  end
end
