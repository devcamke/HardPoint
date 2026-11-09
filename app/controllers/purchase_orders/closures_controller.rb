# Closing a partly delivered order short: the supplier can't send the rest, so it stops being waited for.
class PurchaseOrders::ClosuresController < ApplicationController
  before_action :ensure_can_purchase

  def create
    order = Current.account.purchase_orders.find(params[:purchase_order_id])

    if order.close
      redirect_to order, notice: "Closed short. What never came is no longer on order.", status: :see_other
    else
      redirect_to order, alert: "Only an order with some of its goods received can be closed short; cancel it instead.", status: :see_other
    end
  end
end
