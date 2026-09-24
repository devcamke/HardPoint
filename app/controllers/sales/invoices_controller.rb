# An A4 tax invoice for a sale to a named customer.
class Sales::InvoicesController < ApplicationController
  include SaleScoped

  def show
    return redirect_to @sale, alert: "Only a completed sale to a named customer has an invoice." unless @sale.completed? && @sale.customer

    pdf = SaleInvoicePdf.new(@sale)
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end
end
