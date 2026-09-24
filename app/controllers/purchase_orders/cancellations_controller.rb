class PurchaseOrders::CancellationsController < ApplicationController
  before_action :ensure_can_purchase

  def create
    order = Current.account.purchase_orders.find(params[:purchase_order_id])

    if order.cancel
      redirect_to order, notice: "Cancelled.", status: :see_other
    else
      redirect_to order, alert: "Orders with goods received can't be cancelled.", status: :see_other
    end
  end
end
