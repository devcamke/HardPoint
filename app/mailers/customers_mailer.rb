class CustomersMailer < ApplicationMailer
  helper CatalogueHelper

  def statement
    @customer = params[:customer]
    @account = @customer.account
    @from, @to, @balance_cents = params.values_at(:from, :to, :balance_cents)
    attachments[params[:filename]] = { mime_type: "application/pdf", content: params[:pdf] }

    mail to: @customer.email, reply_to: params[:sender]&.email_address,
      subject: "Your statement from #{@account.name} to #{@to.to_fs(:long)}"
  end
end
