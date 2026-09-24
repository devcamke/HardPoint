class BillingsController < ApplicationController
  include BillingScoped

  def show
    @account = Current.account
    @invoice = @account.open_invoice
    @invoices = @account.billing_invoices.chronologically.limit(24)
    @pending_mpesa = @invoice&.payments&.pending&.where(provider: "mpesa")&.last
  end
end
