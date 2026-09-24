# The goods are in and set aside: the order is ready to collect.
class CustomerOrders::ReadinessesController < ApplicationController
  include CustomerOrderScoped

  def create
    if @customer_order.mark_ready
      redirect_to @customer_order, notice: "Marked ready to collect.", status: :see_other
    else
      redirect_to @customer_order, alert: "Only a confirmed order can be marked ready.", status: :see_other
    end
  end
end
