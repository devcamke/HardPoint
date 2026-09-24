class Billings::InvoicesController < ApplicationController
  include BillingScoped

  def show
    pdf = Billing::InvoicePdf.new(Current.account.billing_invoices.find(params[:id]))
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end
end
