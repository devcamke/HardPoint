# Sending (or sending again) the debit note to the supplier.
class SupplierReturns::EmailsController < ApplicationController
  before_action :ensure_can_purchase

  def create
    supplier_return = Current.account.supplier_returns.find(params[:supplier_return_id])
    return redirect_to supplier_return, alert: "#{supplier_return.supplier.name} has no email address." if supplier_return.supplier.email.blank?

    SupplierReturnsMailer.with(supplier_return: supplier_return).debit_note.deliver_later
    supplier_return.track_event "emailed", to: supplier_return.supplier.email
    redirect_to supplier_return, notice: "Debit note emailed to #{supplier_return.supplier.email}."
  end
end
