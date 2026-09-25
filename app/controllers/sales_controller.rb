class SalesController < ApplicationController
  before_action :ensure_can_sell

  def index
    sales = Current.account.sales.finished.chronologically.includes(:branch, :customer, :cashier, :register)
    if params[:query].present?
      sales = sales.where(id: Current.account.sales.find_by_receipt_number(params[:query])&.id)
    else
      @date = (Date.parse(params[:date]) rescue Time.zone.today)
      sales = sales.where(completed_at: @date.all_day)
      # At a till, show its branch; elsewhere, every branch — unless one is picked.
      @branch = params.key?(:branch_id) ? Current.account.branches.find_by(id: params[:branch_id]) : current_till&.branch
      sales = sales.where(branch: @branch) if @branch
    end
    @sales = paginate(sales)
  end

  def show
    @sale = Current.account.sales.find(params[:id])
    # Which batches the sale took, per product, for tracing a recall back.
    @batches = StockMovement.where(source: @sale, reason: "sold").joins(:stock_batch).group(:product_id, "stock_batches.number")
      .sum("-stock_movements.quantity").each_with_object(Hash.new { _1[_2] = [] }) { |((product_id, number), quantity), by_product| by_product[product_id] << [ number, quantity ] }
  end
end
