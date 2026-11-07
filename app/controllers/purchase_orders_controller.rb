class PurchaseOrdersController < ApplicationController
  include ListGrouping

  GROUPINGS = { "supplier" => "Supplier", "status" => "Status" }.freeze
  BLANK_LINES = 6

  before_action :ensure_can_purchase
  before_action :set_purchase_order, only: %i[ show edit update ]

  def index
    orders = Current.account.purchase_orders.chronologically.includes(:supplier, :branch)
    orders = orders.where(status: params[:status]) if params[:status].in?(PurchaseOrder.statuses.keys)
    orders = orders.open if params[:status] == "open"
    orders = orders.where(supplier_id: Current.account.suppliers.search(params[:query]).select(:id)) if params[:query].present?
    orders = orders.where(supplier: Current.account.suppliers.find(params[:supplier_id])) if params[:supplier_id].present?
    if (@group_by = params[:group_by].presence_in(GROUPINGS.keys))
      @groups = order_groups(orders.joins(:supplier))
    else
      @purchase_orders = paginate(orders)
    end

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
    return create_all_from_suggestions if params[:from_suggestions] && params[:supplier_id] == "all"

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
    # Orders are in their supplier's currency, so each currency is added up on its own.
    def order_groups(orders)
      if @group_by == "supplier"
        names = Current.account.suppliers.pluck(:id, :name).to_h
        list_groups(orders, :supplier_id, labels: names.method(:[]), total: :total_cents, currency: Current.account.currency, currency_column: "suppliers.currency")
      else
        list_groups(orders, :status, labels: ->(status) { status.humanize }, total: :total_cents, currency: Current.account.currency, currency_column: "suppliers.currency",
          order: PurchaseOrder.statuses.keys)
      end
    end

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

    # One draft per supplier from Stock › Reorder, in a single click.
    def create_all_from_suggestions
      branch = Current.account.branches.find(params[:branch_id])
      orders = ReorderSuggestion.new(Current.account, branch).by_supplier.filter_map do |supplier, rows|
        order_from_suggestions(supplier:, branch:, rows:) if supplier
      end
      PurchaseOrder.transaction { orders.each(&:save!) }
      redirect_to purchase_orders_path(status: "draft"), notice: "#{orders.size} draft #{"order".pluralize(orders.size)} saved. Check each one, then send it to the supplier."
    end

    # One click from Stock › Reorder: a draft for this supplier with the suggested quantities.
    def order_from_suggestions(supplier: Current.account.suppliers.find(params[:supplier_id]), branch: Current.account.branches.find(params[:branch_id]), rows: nil)
      rows ||= ReorderSuggestion.new(Current.account, branch).rows.select { _1.supplier_product&.supplier == supplier }

      Current.account.purchase_orders.new(supplier: supplier, branch: branch, expected_on: Date.current + rows.map(&:lead_time).max.to_i.days,
        lines_attributes: rows.map { { account: Current.account, product: _1.product, quantity: _1.quantity, unit_cost_cents: _1.supplier_product.cost_cents } })
    end

    def add_blank_lines
      (BLANK_LINES - @purchase_order.lines.count(&:new_record?)).clamp(1, BLANK_LINES).times { @purchase_order.lines.build }
    end
end
