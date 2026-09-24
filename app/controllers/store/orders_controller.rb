# Where an online customer follows their order, by the unguessable link in their text or email.
class Store::OrdersController < Store::BaseController
  def show
    @order = Current.account.customer_orders.online.includes(:branch, :customer, lines: :product).find_by!(tracking_token: params[:token].to_s)
    @paybill = Current.account.mpesa_shortcodes.for_branch(@order.branch)
  end
end
