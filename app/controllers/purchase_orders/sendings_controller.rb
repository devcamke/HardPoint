# Sending a draft: emailed to the supplier with the PDF attached, or just marked sent when the
# order went by phone or WhatsApp. An order over the shop's limit needs an owner or manager (PurchaseOrder).
class PurchaseOrders::SendingsController < ApplicationController
  before_action :ensure_can_purchase

  def create
    order = Current.account.purchase_orders.find(params[:purchase_order_id])
    email = params[:email] == "1" && order.supplier.email.present?

    approver = approver_for_action if order.needs_approval?

    if order.draft? && order.needs_approval? && approver.nil?
      redirect_to order, alert: "An order over #{helpers.money(Current.account.purchase_approval_above_cents)} needs a manager's approval PIN to send.", status: :see_other
    elsif order.mark_sent(approver: approver)
      PurchaseOrdersMailer.with(purchase_order: order).placed.deliver_later if email
      redirect_to order, notice: email ? "Sent to #{order.supplier.email} with the PDF attached." : "Marked as sent.", status: :see_other
    else
      redirect_to order, alert: "Only a draft can be sent.", status: :see_other
    end
  end
end
