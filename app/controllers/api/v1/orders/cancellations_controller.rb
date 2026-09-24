class Api::V1::Orders::CancellationsController < Api::V1::BaseController
  def create
    @order = Current.account.customer_orders.find(params[:order_id])
    if @order.cancel(reason: params[:reason].presence || "Cancelled through the API")
      render "api/v1/orders/show"
    else
      render_error :unprocessable_entity, "not_cancellable", @order.errors.full_messages.to_sentence.presence || "A #{@order.status} order can't be cancelled."
    end
  end
end
