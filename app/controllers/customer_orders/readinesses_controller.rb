# The goods are in and set aside: the order is ready to collect.
class CustomerOrders::ReadinessesController < ApplicationController
  include CustomerOrderScoped

  def create
    if @customer_order.mark_ready
      text = Sms::Message.order_ready(@customer_order) if params[:notify] == "1"
      notice = text&.persisted? ? "Marked ready, and #{@customer_order.customer.name} has been sent a text." : "Marked ready to collect."
      redirect_to @customer_order, notice: notice, alert: text&.errors&.full_messages&.to_sentence.presence, status: :see_other
    else
      redirect_to @customer_order, alert: "Only a confirmed order can be marked ready.", status: :see_other
    end
  end
end
