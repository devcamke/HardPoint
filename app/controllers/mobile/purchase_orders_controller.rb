# Deliveries expected (orders sent to suppliers), and checking one in by scanning.
class Mobile::PurchaseOrdersController < Mobile::BaseController
  include MobileReceiving
  skip_before_action :set_purchase_order, only: :index

  def index
    @orders = Current.account.purchase_orders.where(status: %w[ sent partially_received ]).includes(:supplier, :branch).order(:expected_on, :id)
  end

  def show
    return redirect_to mobile_purchase_orders_path, alert: "#{@order.reference} is #{@order.status.humanize.downcase}." unless @order.receivable?
    draft
  end
end
