class PurchaseOrdersController < ApplicationController
  BLANK_LINES = 6

  before_action :ensure_can_purchase
  before_action :set_purchase_order, only: %i[ show edit update ]

  def index
    orders = Current.account.purchase_orders.chronologically.includes(:supplier, :branch)
    orders = orders.where(status: params[:status]) if params[:status].in?(PurchaseOrder.statuses.keys)
    orders = orders.open if params[:status] == "open"
    @purchase_orders = paginate(orders)

    respond_to do |format|
      format.html
    end
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        pdf = PurchaseOrderPdf.new(@purchase_order)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end

  def new
    @purchase_order = Current.account.purchase_orders.new(branch: selected_branch,
      supplier: Current.account.suppliers.find_by(id: params[:supplier_id]))
    BLANK_LINES.times { @purchase_order.lines.build }
  end

  def create
    @purchase_order = params[:from_suggestions] ? order_from_suggestions : Current.account.purchase_orders.new(purchase_order_params)

    if @purchase_order.save
      redirect_to @purchase_order, notice: "Draft #{@purchase_order.reference} saved. Check it, then send it to #{@purchase_order.supplier.name}."
    else
      add_blank_lines
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return redirect_to @purchase_order, alert: "Only a draft can be changed." unless @purchase_order.draft?
    add_blank_lines
  end

  def update
    if @purchase_order.draft? && @purchase_order.update(purchase_order_params)
      redirect_to @purchase_order, notice: "Saved."
    else
      @purchase_order.errors.add :base, "Only a draft can be changed" unless @purchase_order.draft?
      add_blank_lines
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_purchase_order
      @purchase_order = Current.account.purchase_orders.find(params[:id])
    end

    def purchase_order_params
      permitted = params.expect(purchase_order: [ :supplier_id, :branch_id, :expected_on, :note,
        lines_attributes: [ [ :id, :product_code, :quantity, :unit_cost, :_destroy ] ] ])
      permitted[:supplier] = Current.account.suppliers.find(permitted.delete(:supplier_id)) if permitted.key?(:supplier_id)
      permitted[:branch] = Current.account.branches.find(permitted.delete(:branch_id)) if permitted.key?(:branch_id)
      permitted[:lines_attributes]&.each_value { |line| line[:account] = Current.account if line[:id].blank? }
      permitted
    end

    # One click from the reorder suggestions: a draft for this supplier with the suggested quantities.
    def order_from_suggestions
      supplier = Current.account.suppliers.find(params[:supplier_id])
      branch = Current.account.branches.find(params[:branch_id])
      rows = ReorderSuggestion.new(Current.account, branch).rows.select { _1.supplier_product&.supplier == supplier }

      Current.account.purchase_orders.new(supplier: supplier, branch: branch, expected_on: Date.current + rows.map(&:lead_time).max.to_i.days,
        lines_attributes: rows.map { { account: Current.account, product: _1.product, quantity: _1.quantity, unit_cost_cents: _1.supplier_product.cost_cents } })
    end

    def add_blank_lines
      (BLANK_LINES - @purchase_order.lines.count(&:new_record?)).clamp(1, BLANK_LINES).times { @purchase_order.lines.build }
    end
end
