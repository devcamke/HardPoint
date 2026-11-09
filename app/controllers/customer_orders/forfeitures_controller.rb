# Keeping an order's deposit when the customer isn't coming back: rung through this device's till as a sale of
# "Forfeited deposit" paid from the deposit, then the order is cancelled. A manager approves, at the till or by PIN.
class CustomerOrders::ForfeituresController < ApplicationController
  include CustomerOrderScoped
  before_action :require_till_and_shift

  def create
    if @customer_order.forfeit_deposit(shift: current_shift, approver: approver_for_action, reason: params[:reason])
      redirect_to @customer_order, notice: "Deposit kept and #{@customer_order.reference} cancelled.", status: :see_other
    else
      redirect_to @customer_order, alert: @customer_order.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
