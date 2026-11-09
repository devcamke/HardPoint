# A customer paying off their account, at the counter (cash goes into this device's till) or by
# M-Pesa, bank transfer or cheque; or, with ?refund=1, credit left on their account handed back to them.
# A payment settles the oldest sales first unless it's put against particular ones.
class Customers::PaymentsController < ApplicationController
  include CustomerPaymentEntries
  before_action :ensure_can_sell_or_manage_receivables, :set_customer

  def new
    @refund = params[:refund].present?
    @payment = @customer.customer_payments.new(kind: @refund ? "refund" : "payment", paid_on: Date.current,
      amount_cents: [ @refund ? -@customer.balance_cents : @customer.balance_cents, 0 ].max,
      payment_method: current_shift ? "cash" : "mobile_money")
  end

  def create
    @refund = params[:refund].present?
    @payment = build_entry(kind: @refund ? "refund" : "payment", permitted: %i[ paid_on amount payment_method reference note ])
    @payment.shift = current_shift if @payment.payment_method == "cash"

    if @payment.save
      redirect_to @customer, notice: "#{@refund ? "Refund" : "Payment"} of #{Money.format(@payment.amount_cents.abs)} recorded. #{owed_now}"
    else
      render :new, status: :unprocessable_entity
    end
  end
end
