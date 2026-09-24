class CustomerOrders::CancellationsController < ApplicationController
  include CustomerOrderScoped

  def create
    if @customer_order.cancel(reason: params[:reason])
      redirect_to @customer_order, notice: "#{@customer_order.kind} cancelled.", status: :see_other
    else
      redirect_to @customer_order, alert: @customer_order.errors.full_messages.to_sentence.presence || "This can't be cancelled.", status: :see_other
    end
  end
end
