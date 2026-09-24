# Collecting an order: it's put into this device's till at the agreed prices, and completing the
# sale there marks it collected.
class CustomerOrders::CollectionsController < ApplicationController
  include CustomerOrderScoped
  before_action :require_till_and_shift

  def create
    if @customer_order.load_into(current_shift.current_sale)
      redirect_to pos_path, notice: "#{@customer_order.reference} is in the till.", status: :see_other
    else
      redirect_to @customer_order, alert: @customer_order.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
