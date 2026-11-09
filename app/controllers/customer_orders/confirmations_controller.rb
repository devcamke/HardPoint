# The customer accepts a quote: it becomes an order at the quoted prices. One worth more than the customer's
# credit left needs a manager's say-so, at their own screen or by approval PIN.
class CustomerOrders::ConfirmationsController < ApplicationController
  include CustomerOrderScoped

  def create
    if @customer_order.confirm(approver: approver_for_action)
      redirect_to @customer_order, notice: "#{@customer_order.reference} is now an order.", status: :see_other
    else
      redirect_to @customer_order, alert: @customer_order.errors.full_messages.to_sentence.presence || "Only a quote can be confirmed.", status: :see_other
    end
  end
end
