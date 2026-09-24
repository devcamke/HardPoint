# Sending a draft: emailed to the supplier with the PDF attached, or just marked sent when the
# order went by phone or WhatsApp.
class PurchaseOrders::SendingsController < ApplicationController
  before_action :ensure_can_purchase

  def create
    order = Current.account.purchase_orders.find(params[:purchase_order_id])
    email = params[:email] == "1" && order.supplier.email.present?

    if order.mark_sent
      PurchaseOrdersMailer.with(purchase_order: order).placed.deliver_later if email
      redirect_to order, notice: email ? "Sent to #{order.supplier.email} with the PDF attached." : "Marked as sent.", status: :see_other
    else
      redirect_to order, alert: "Only a draft can be sent.", status: :see_other
    end
  end
end
