module Sale::Cart
  extend ActiveSupport::Concern

  CART_LINE_ASSOCIATIONS = [ :product, :promotion, { product_unit: :unit } ].freeze

  # Adds a product (or one of its packs) to the cart. Scanning the same thing again adds to the
  # existing line; serialised products get a line each, for their serial number.
  def add(product, product_unit: nil, quantity: 1)
    raise ArgumentError, "This sale can't be changed" unless open?

    existing = lines.find { |line| line.product_id == product.id && line.product_unit_id == product_unit&.id && !product.serialized? && line.discount_cents.zero? && line.customer_order_line_id.nil? }
    line = if existing
      existing.quantity += quantity.to_d
      existing
    else
      lines.build(account: account, product: product, product_unit: product_unit, quantity: quantity)
    end

    line.reprice
    transaction { line.save && recalculate }
    line
  end

  # Transport to the customer's site at what the trip costs, as its own line on this sale.
  def add_transport(amount_cents:, destination: nil)
    raise ArgumentError, "This sale can't be changed" unless open?

    line = lines.build(account: account, product: account.transport_product, quantity: 1, unit_price_cents: amount_cents.to_i,
      detail: destination.to_s.squish.presence&.then { "to #{_1.first(80)}" })
    line.errors.add :base, "Enter what the transport costs" unless amount_cents.to_i.positive?
    transaction { line.save && recalculate } if line.errors.empty?
    line
  end

  def transport_cents
    lines.select(&:transport?).sum(&:total_cents)
  end

  def change_customer(customer)
    raise ArgumentError, "The customer of an order can't be changed" if customer_order && customer != customer_order.customer

    self.customer = customer
    self.job = nil unless job&.customer_id == customer&.id
    lines.each(&:reprice)
    transaction do
      lines.each(&:save!)
      recalculate
    end
  end

  # Totals: line totals after line discounts, less the cart discount. Tax is the tax-inclusive
  # share of each line, scaled down by the cart discount.
  def recalculate
    reload_lines
    apply_bundles
    self.subtotal_cents = lines.sum(&:total_cents)
    self.discount_cents = discount_cents.to_i.clamp(0, subtotal_cents)
    self.total_cents = subtotal_cents - discount_cents
    line_tax = lines.sum(&:tax_cents)
    self.tax_cents = subtotal_cents.zero? ? 0 : (line_tax * total_cents.to_r / subtotal_cents).round
    save!
  end

  # Promotions running today at this sale's branch, looked up once per sale.
  def running_promotions
    @running_promotions ||= account.running_promotions.select { _1.available_at?(branch) }
  end

  # Reloaded with what the till's cart shows, so drawing it doesn't query line by line.
  def reload_for_cart
    reload
    ActiveRecord::Associations::Preloader.new(records: [ self ], associations: { lines: CART_LINE_ASSOCIATIONS }).call
    self
  end

  # The lines afresh, with what bundles, prices and checks read from each one, so that isn't a query per line.
  def reload_lines
    lines.reload
    ActiveRecord::Associations::Preloader.new(records: lines.to_a, associations: CART_LINE_ASSOCIATIONS).call
    lines
  end

  def item_count
    lines.sum(&:quantity)
  end

  # The largest discount on the sale, as a percentage of what was discounted.
  def highest_discount_percent
    line_percents = lines.map(&:discount_percent)
    cart_percent = subtotal_cents.positive? ? discount_cents * 100.0 / subtotal_cents : 0
    [ *line_percents, cart_percent ].max || 0
  end

  # Beyond the cashier's limit, and beyond anything a manager already approved on this sale.
  def discount_needs_approval?
    allowed = [ account.max_cashier_discount_percent.to_f, approved_discount_percent.to_f ].max
    highest_discount_percent > allowed + 0.001
  end
end
