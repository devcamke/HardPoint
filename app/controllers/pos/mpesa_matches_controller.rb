# Using an M-Pesa payment that arrived on the Paybill or Till (the customer paid from their phone
# without a prompt) for the sale on the till.
class Pos::MpesaMatchesController < ApplicationController
  include PosSale

  def create
    transaction = Current.account.mpesa_transactions.unmatched.find(params[:transaction_id])
    payment = transaction.attach_to(@sale)

    if payment.errors.any?
      render_cart alert: payment.errors.full_messages.to_sentence, status: :unprocessable_entity
    elsif @sale.reload.completed?
      redirect_to pos_path(completed: @sale.id), status: :see_other
    else
      render_cart message: "M-Pesa #{transaction.trans_id} used. #{Money.format(@sale.balance_due_cents)} still due."
    end
  rescue ArgumentError => error
    render_cart alert: error.message, status: :unprocessable_entity
  end
end
