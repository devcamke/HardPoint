# A customer paying off their account, at the counter (cash goes into this device's till) or by
# M-Pesa, bank transfer or cheque.
class Customers::PaymentsController < ApplicationController
  before_action :ensure_can_sell_or_manage_receivables, :set_customer

  def new
    @payment = @customer.customer_payments.new(paid_on: Date.current, amount_cents: [ @customer.balance_cents, 0 ].max,
      payment_method: current_shift ? "cash" : "mobile_money")
  end

  def create
    @payment = @customer.customer_payments.new(params.expect(customer_payment: %i[ paid_on amount payment_method reference note ]).merge(account: Current.account))
    @payment.shift = current_shift if @payment.payment_method == "cash"

    if @payment.save
      redirect_to @customer, notice: "Payment of #{Money.format(@payment.amount_cents)} recorded. #{@customer.name} now owes #{Money.format(@customer.balance_cents)}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_customer
      @customer = Current.account.customers.find(params[:customer_id])
    end
end
