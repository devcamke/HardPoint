class SalesMailer < ApplicationMailer
  helper CatalogueHelper

  def receipt
    @sale = params[:sale]
    @account = @sale.account
    mail to: params[:email], subject: "Your receipt from #{@account.name} (#{@sale.receipt_number})"
  end
end
