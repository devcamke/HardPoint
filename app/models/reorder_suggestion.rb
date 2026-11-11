# What to order for a branch, and from whom. For each stocked product it looks at stock on hand, what's already on
# order (or on its way from another branch), and what DemandForecast learns from the branch's history: daily demand
# (sales plus what the till turned away, adjusted for the season), a safety margin for busy days, and how long the
# supplier really takes:
#
#   cover wanted = the larger of twice the reorder level, or demand for (lead time + 14 days) plus the safety margin
#   suggestion   = cover wanted − on hand − on order, rounded up to the supplier's minimum order
#
# Stock promised to customers' confirmed orders isn't there for anyone else, so it counts against what's on hand.
#
# A product is suggested when it's at or below its reorder level (the branch's own, if it has set one,
# else the product's), or won't last the lead time.
class ReorderSuggestion
  EXTRA_COVER_DAYS = 14

  # needed is what's short before rounding up to the supplier's order size; quantity is what to order.
  Row = Data.define(:product, :supplier_product, :on_hand, :on_order, :held, :sold, :daily_sales, :lead_time, :reorder_level, :needed, :quantity, :forecast) do
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
    on_hand = levels.fetch(product.id, 0) - reserved.fetch(product.id, 0) # what's held for orders here can't be moved away
    return 0 unless on_hand.positive?

    expected = forecast.for(product, supplier_product: product.preferred_supplier_product)
    reorder_level = reorder_levels.fetch(product.id, product.reorder_level)
    wanted = [ reorder_level * 2, expected.daily * (expected.lead_time + EXTRA_COVER_DAYS) + expected.safety, reorder_level + 1 ].max
    surplus = on_hand - wanted
    return 0 unless surplus.positive?

    product.unit.fractional? ? surplus.round(1, BigDecimal::ROUND_DOWN) : surplus.floor
  end

  def on_hand(product) = levels.fetch(product.id, 0)

  # Suggestions grouped by preferred supplier (nil for products with no supplier yet).
  def by_supplier
    rows.group_by { _1.supplier_product&.supplier }.sort_by { |supplier, _| supplier ? [ 0, supplier.name ] : [ 1, "" ] }
  end

  private
    # Products with demand here, and the rest only when the shelf is at or below their reorder level: with nothing
    # selling, nothing else can need ordering. Filtered in the database, so a big catalogue with few products short
    # isn't loaded to find them.
    def candidates
      level = "COALESCE(shelf.reorder_level, products.reorder_level)"
      @account.products.active.where(track_stock: true)
        .joins(ActiveRecord::Base.sanitize_sql_array([ "LEFT JOIN stock_levels shelf ON shelf.product_id = products.id AND shelf.branch_id = ?", @branch.id ]))
        .where("products.id IN (?) OR (#{level} > 0 AND COALESCE(shelf.quantity, 0) <= #{level})", (forecast.product_ids | reserved.keys).presence || [ 0 ])
        .includes(:unit, supplier_products: :supplier)
    end

    def row_for(product)
      on_hand = levels.fetch(product.id, 0)
      on_order = ordered.fetch(product.id, 0)
      held = reserved.fetch(product.id, 0)
      supplier_product = product.preferred_supplier_product
      expected = forecast.for(product, supplier_product: supplier_product)
      daily, lead_time = expected.daily, expected.lead_time
      reorder_level = reorder_levels.fetch(product.id, product.reorder_level)

      available = on_hand + on_order - held
      return unless available <= reorder_level || available < daily * lead_time + expected.safety

      wanted = [ reorder_level * 2, daily * (lead_time + EXTRA_COVER_DAYS) + expected.safety ].max
      needed = wanted - available
      return unless needed.positive?

      needed = product.unit.fractional? ? needed.round(1, BigDecimal::ROUND_UP) : needed.ceil
      quantity = supplier_product ? supplier_product.order_quantity_for(needed) : needed
      Row.new(product:, supplier_product:, on_hand:, on_order:, held:, sold: expected.sold, daily_sales: daily, lead_time:, reorder_level:, needed:, quantity:, forecast: expected)
    end

    def forecast = @forecast ||= DemandForecast.new(@account, @branch)

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

    # Promised to confirmed orders here and not yet collected, in the base unit (Product#reserved_at, for every product).
    def reserved
      @reserved ||= CustomerOrderLine.joins(:customer_order).left_joins(:product_unit)
        .where(customer_orders: { branch_id: @branch.id, status: %w[ ordered ready ] })
        .group(:product_id).sum("GREATEST(customer_order_lines.quantity - customer_order_lines.collected_quantity, 0) * COALESCE(product_units.quantity, 1)")
        .select { _2.positive? }
    end

    def in_transit
      StockTransferLine.joins(:stock_transfer).where(stock_transfers: { to_branch_id: @branch.id, status: "in_transit" }).group(:product_id).sum(:quantity)
    end
end
