class Pos::PaymentsController < ApplicationController
  include PosSale

  def create
    payment = @sale.pay(tender: params[:tender], amount_cents: Monetary.to_cents(params[:amount]),
      tendered_cents: Monetary.to_cents(params[:tendered]), reference: params[:reference],
      credit_approver: (approver_for_action if params[:tender] == "on_account"))

    if payment.errors.any?
      render_cart alert: payment.errors.full_messages.to_sentence, status: :unprocessable_entity
    elsif @sale.reload.completed?
      redirect_to pos_path(completed: @sale.id), status: :see_other
    else
      render_cart message: "#{payment.label} #{Money.format(payment.amount_cents)} taken. #{Money.format(@sale.balance_due_cents)} still due."
    end
  end

  def destroy
    @sale.remove_payment(@sale.payments.find(params[:id]))
    render_cart message: "Payment removed"
  end
end
