class GoodsReceiptsController < ApplicationController
  BLANK_LINES = 8

  before_action :ensure_can_purchase

  def index
    @goods_receipts = paginate(Current.account.goods_receipts.chronologically.includes(:supplier, :branch, :purchase_order, :receiver))
  end

  def show
    @goods_receipt = Current.account.goods_receipts.find(params[:id])
  end

  # Against an order: its outstanding lines, ready to confirm. Without one: blank lines to scan into.
  def new
    order = Current.account.purchase_orders.find_by(id: params[:purchase_order_id])
    @goods_receipt = Current.account.goods_receipts.new(purchase_order: order, supplier: order&.supplier, branch: order&.branch || selected_branch)

    if order
      return redirect_to order, alert: "This order is #{order.status.humanize.downcase}." unless order.receivable?
      order.outstanding_lines.each { |line| @goods_receipt.lines.build(purchase_order_line: line, product: line.product, quantity: line.outstanding_quantity, unit_cost_cents: line.unit_cost_cents) }
    else
      BLANK_LINES.times { @goods_receipt.lines.build }
    end
  end

  def create
    @goods_receipt = Current.account.goods_receipts.new(goods_receipt_params)

    if @goods_receipt.save
      redirect_to @goods_receipt, notice: "Received into #{@goods_receipt.branch.name}. Stock and costs are updated."
    else
      BLANK_LINES.times { @goods_receipt.lines.build } unless @goods_receipt.purchase_order
      render :new, status: :unprocessable_entity
    end
  end

  private
    def goods_receipt_params
      permitted = params.expect(goods_receipt: [ :supplier_id, :branch_id, :purchase_order_id, :supplier_reference, :extra_costs, :note, :exchange_rate,
        lines_attributes: [ [ :purchase_order_line_id, :product_code, :quantity, :unit_cost, :batch_number, :expires_on ] ] ])
      order = Current.account.purchase_orders.find(permitted.delete(:purchase_order_id)) if permitted[:purchase_order_id].present?

      permitted[:purchase_order] = order
      permitted[:supplier] = order&.supplier || Current.account.suppliers.find(permitted.delete(:supplier_id))
      permitted[:branch] = order&.branch || Current.account.branches.find(permitted.delete(:branch_id))
      permitted.delete(:supplier_id)
      permitted.delete(:branch_id)
      permitted[:lines_attributes]&.each_value do |line|
        line[:account] = Current.account
        line[:purchase_order_line] = order.lines.find(line.delete(:purchase_order_line_id)) if order && line[:purchase_order_line_id].present?
      end
      permitted
    end
end
