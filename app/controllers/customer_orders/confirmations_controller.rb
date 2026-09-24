# The customer accepts a quote: it becomes an order at the quoted prices.
class CustomerOrders::ConfirmationsController < ApplicationController
  include CustomerOrderScoped

  def create
    if @customer_order.confirm
      redirect_to @customer_order, notice: "#{@customer_order.reference} is now an order.", status: :see_other
    else
      redirect_to @customer_order, alert: @customer_order.errors.full_messages.to_sentence.presence || "Only a quote can be confirmed.", status: :see_other
    end
  end
end
