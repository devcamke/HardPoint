# The supplier's credit note has arrived: its number is kept against the debit note.
class SupplierReturns::CreditNotesController < ApplicationController
  before_action :ensure_can_purchase_or_pay

  def create
    supplier_return = Current.account.supplier_returns.find(params[:supplier_return_id])
    if supplier_return.record_credit_note(number: params[:credit_note_number], on: params[:credited_on].presence&.to_date || Date.current)
      redirect_to supplier_return, notice: "Credit note #{supplier_return.credit_note_number} noted."
    else
      redirect_to supplier_return, alert: supplier_return.errors.full_messages.to_sentence
    end
  end
end
