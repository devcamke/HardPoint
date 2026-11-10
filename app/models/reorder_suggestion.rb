# What to order for a branch, and from whom. For each stocked product it looks at stock on hand,
# what's already on order (or on its way from another branch), sales over the shop's look-back period (30 days
# unless Settings › Shop preferences says otherwise) and the supplier's lead time (or the shop's usual one):
#
#   cover wanted = the larger of twice the reorder level, or enough to sell for (lead time + 14 days)
#   suggestion   = cover wanted − on hand − on order, rounded up to the supplier's minimum order
#
# A product is suggested when it's at or below its reorder level (the branch's own, if it has set one,
# else the product's), or won't last the lead time.
class ReorderSuggestion
  EXTRA_COVER_DAYS = 14

  Row = Data.define(:product, :supplier_product, :on_hand, :on_order, :sold, :daily_sales, :lead_time, :reorder_level, :quantity) do
    def cost_cents = ((supplier_product&.cost_cents || product.cost_cents) * quantity).round
  end

  def initialize(account, branch)
    @account, @branch = account, branch
  end

  def rows
    @rows ||= candidates.filter_map { |product| row_for(product) }.sort_by { [ -_1.quantity * _1.product.cost_cents, _1.product.name ] }
  end

  # Suggestions grouped by preferred supplier (nil for products with no supplier yet).
  def by_supplier
    rows.group_by { _1.supplier_product&.supplier }.sort_by { |supplier, _| supplier ? [ 0, supplier.name ] : [ 1, "" ] }
  end

  private
    def candidates
      @account.products.active.where(track_stock: true)
        .where("products.reorder_level > 0 OR products.id IN (?)", (sold.keys + reorder_levels.keys).presence || [ 0 ])
        .includes(:unit, supplier_products: :supplier)
    end

    def row_for(product)
      on_hand = levels.fetch(product.id, 0)
      on_order = ordered.fetch(product.id, 0)
      sold_quantity = sold.fetch(product.id, 0)
      daily = sold_quantity / @account.reorder_lookback_days
      supplier_product = product.preferred_supplier_product
      lead_time = supplier_product&.lead_time_days || @account.supplier_lead_time_days
      reorder_level = reorder_levels.fetch(product.id, product.reorder_level)

      available = on_hand + on_order
      return unless available <= reorder_level || available < daily * lead_time

      wanted = [ reorder_level * 2, daily * (lead_time + EXTRA_COVER_DAYS) ].max
      needed = wanted - available
      return unless needed.positive?

      needed = product.unit.fractional? ? needed.round(1, BigDecimal::ROUND_UP) : needed.ceil
      quantity = supplier_product ? supplier_product.order_quantity_for(needed) : needed
      Row.new(product:, supplier_product:, on_hand:, on_order:, sold: sold_quantity, daily_sales: daily, lead_time:, reorder_level:, quantity:)
    end

    def levels
      @levels ||= StockLevel.where(branch: @branch).pluck(:product_id, :quantity).to_h
    end

    # The branch's own reorder levels, for the products it has set one on.
    def reorder_levels
      @reorder_levels ||= StockLevel.where(branch: @branch).where.not(reorder_level: nil).pluck(:product_id, :reorder_level).to_h
    end

    # Ordered but not yet received, on orders already sent to suppliers, plus what another branch
    # has sent and hasn't arrived yet: both turn up without ordering more.
    def ordered
      @ordered ||= PurchaseOrderLine.joins(:purchase_order)
        .where(purchase_orders: { branch_id: @branch.id, status: %w[ sent partially_received ] })
        .group(:product_id).sum("purchase_order_lines.quantity - purchase_order_lines.received_quantity")
        .merge(in_transit) { |_, on_order, coming| on_order + coming }
    end

    def in_transit
      StockTransferLine.joins(:stock_transfer).where(stock_transfers: { to_branch_id: @branch.id, status: "in_transit" }).group(:product_id).sum(:quantity)
    end

    def sold
      @sold ||= StockMovement.where(branch: @branch, reason: %w[ sold returned ], created_at: @account.reorder_lookback_days.days.ago..)
        .group(:product_id).sum(:quantity).transform_values { -_1 }.select { |_, quantity| quantity.positive? }
    end
end
