class Api::V1::Orders::CancellationsController < Api::V1::BaseController
  def create
    @order = find_related(Current.account.customer_orders, params[:order_id], field: :order_id, name: "order")
    if @order.cancel(reason: params[:reason].presence || "Cancelled through the API")
      render "api/v1/orders/show"
    else
      render_error :unprocessable_entity, "not_cancellable", @order.errors.full_messages.to_sentence.presence || "A #{@order.status} order can't be cancelled."
    end
  end
end
