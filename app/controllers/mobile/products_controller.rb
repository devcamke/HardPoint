# Point the camera at anything on the shelf: what it is, its prices, and how many are where.
class Mobile::ProductsController < Mobile::BaseController
  def index
    @products = Current.account.products.active.search(params[:query]).includes(:unit).limit(20) if params[:query].present?
  end

  def show
    @product = if params[:id] == "scan"
      scanned.product or return render(:not_found, status: :not_found)
    else
      Current.account.products.find(params[:id])
    end

    @levels = StockLevel.where(product: @product).index_by(&:branch_id)
    @branches = Current.account.branches.alphabetically
    @on_order = PurchaseOrderLine.joins(:purchase_order).where(product: @product, purchase_orders: { status: %w[ sent partially_received ] })
      .group("purchase_orders.branch_id").sum("purchase_order_lines.quantity - purchase_order_lines.received_quantity")
    @movements = @product.stock_movements.where(branch: selected_branch).order(created_at: :desc).limit(5)
  end
end
