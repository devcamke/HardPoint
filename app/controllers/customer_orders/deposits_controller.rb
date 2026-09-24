# Deposits on an order, and refunds of them (a negative deposit). Cash goes through this
# device's till, so it needs an open shift there.
class CustomerOrders::DepositsController < ApplicationController
  include CustomerOrderScoped

  def new
    @refund = params[:refund].present?
    @deposit = @customer_order.deposits.new(tender: current_shift ? "cash" : "mobile_money",
      amount_cents: @refund ? @customer_order.deposit_balance_cents : nil)
  end

  def create
    @refund = params[:refund].present?
    attributes = params.expect(deposit: %i[ amount tender reference ])
    arguments = { amount_cents: Monetary.to_cents(attributes[:amount]).to_i, tender: attributes[:tender], reference: attributes[:reference],
                  shift: (current_shift if attributes[:tender] == "cash") }
    @deposit = @refund ? @customer_order.refund_deposit(**arguments) : @customer_order.take_deposit(**arguments)

    if @deposit.persisted?
      redirect_to @customer_order, notice: "#{@refund ? "Refunded" : "Deposit of"} #{Money.format(@deposit.amount_cents.abs)}#{" to the customer" if @refund} recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
