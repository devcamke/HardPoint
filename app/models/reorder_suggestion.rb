# What to order for a branch, and from whom. For each stocked product it looks at stock on hand, what's already on
# order (or on its way from another branch), and what DemandForecast learns from the branch's history: daily demand
# (sales plus what the till turned away, adjusted for the season), a safety margin for busy days, and how long the
# supplier really takes:
#
#   cover wanted = the larger of twice the reorder level, or demand for (lead time + 14 days) plus the safety margin
#   suggestion   = cover wanted − on hand − on order, rounded up to the supplier's minimum order
#
# A product is suggested when it's at or below its reorder level (the branch's own, if it has set one,
# else the product's), or won't last the lead time.
class ReorderSuggestion
  EXTRA_COVER_DAYS = 14

  # needed is what's short before rounding up to the supplier's order size; quantity is what to order.
  Row = Data.define(:product, :supplier_product, :on_hand, :on_order, :sold, :daily_sales, :lead_time, :reorder_level, :needed, :quantity, :forecast) do
    # A reorder level the branch's history suggests, when it differs from the one set: higher whenever demand says so,
    # lower only once the product has sold here on enough days to be sure.
    def suggested_level
      level = forecast.suggested_level
      return unless level.positive? && level != reorder_level
      return if level < reorder_level && forecast.sales_days < DemandForecast::EVIDENCE_DAYS

      level
    end

    def cost_cents = ((supplier_product&.cost_cents || product.cost_cents) * quantity).round
  end

  def initialize(account, branch)
    @account, @branch = account, branch
  end

  def rows
    @rows ||= candidates.filter_map { |product| row_for(product) }.sort_by { [ -_1.quantity * _1.product.cost_cents, _1.product.name ] }
  end

  # What this branch could spare of a product: what it holds beyond the cover it wants for itself (the same cover a
  # suggestion aims for), so moving it away never leaves the branch needing to reorder. Nothing for one that's short.
  def spare(product)
    on_hand = levels.fetch(product.id, 0)
    return 0 unless on_hand.positive?

    expected = forecast.for(product, supplier_product: product.preferred_supplier_product)
    reorder_level = reorder_levels.fetch(product.id, product.reorder_level)
    wanted = [ reorder_level * 2, expected.daily * (expected.lead_time + EXTRA_COVER_DAYS) + expected.safety, reorder_level + 1 ].max
    surplus = on_hand - wanted
    return 0 unless surplus.positive?

    product.unit.fractional? ? surplus.round(1, BigDecimal::ROUND_DOWN) : surplus.floor
  end

  def on_hand(product) = levels.fetch(product.id, 0)

  # Orders drafted for this branch and not yet sent, whose lines count as on order.
  def draft_orders
    @account.purchase_orders.draft.where(branch: @branch).includes(:supplier).order(:created_at)
  end

  # Suggestions grouped by preferred supplier (nil for products with no supplier yet).
  def by_supplier
    rows.group_by { _1.supplier_product&.supplier }.sort_by { |supplier, _| supplier ? [ 0, supplier.name ] : [ 1, "" ] }
  end

  private
    def candidates
      @account.products.active.where(track_stock: true)
        .where("products.reorder_level > 0 OR products.id IN (?)", (forecast.product_ids + reorder_levels.keys).presence || [ 0 ])
        .includes(:unit, supplier_products: :supplier)
    end

    def row_for(product)
      on_hand = levels.fetch(product.id, 0)
      on_order = ordered.fetch(product.id, 0)
      supplier_product = product.preferred_supplier_product
      expected = forecast.for(product, supplier_product: supplier_product)
      daily, lead_time = expected.daily, expected.lead_time
      reorder_level = reorder_levels.fetch(product.id, product.reorder_level)

      available = on_hand + on_order
      return unless available <= reorder_level || available < daily * lead_time + expected.safety

      wanted = [ reorder_level * 2, daily * (lead_time + EXTRA_COVER_DAYS) + expected.safety ].max
      needed = wanted - available
      return unless needed.positive?

      needed = product.unit.fractional? ? needed.round(1, BigDecimal::ROUND_UP) : needed.ceil
      quantity = supplier_product ? supplier_product.order_quantity_for(needed) : needed
      Row.new(product:, supplier_product:, on_hand:, on_order:, sold: expected.sold, daily_sales: daily, lead_time:, reorder_level:, needed:, quantity:, forecast: expected)
    end

    def forecast = @forecast ||= DemandForecast.new(@account, @branch)

    def levels
      @levels ||= StockLevel.where(branch: @branch).pluck(:product_id, :quantity).to_h
    end

    # The branch's own reorder levels, for the products it has set one on.
    def reorder_levels
      @reorder_levels ||= StockLevel.where(branch: @branch).where.not(reorder_level: nil).pluck(:product_id, :reorder_level).to_h
    end

    # Ordered but not yet received, plus what another branch has sent and hasn't arrived yet: both turn up without
    # ordering more. Draft orders count too, so drafting from these suggestions twice doesn't order everything twice;
    # the Reorder page lists the drafts still to send (draft_orders).
    def ordered
      @ordered ||= PurchaseOrderLine.joins(:purchase_order)
        .where(purchase_orders: { branch_id: @branch.id, status: %w[ draft sent partially_received ] })
        .group(:product_id).sum("purchase_order_lines.quantity - purchase_order_lines.received_quantity")
        .merge(in_transit) { |_, on_order, coming| on_order + coming }
    end

    def in_transit
      StockTransferLine.joins(:stock_transfer).where(stock_transfers: { to_branch_id: @branch.id, status: "in_transit" }).group(:product_id).sum(:quantity)
    end
end
