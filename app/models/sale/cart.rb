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
    if (shortage = stock_shortfall(only: line))
      # Put the cart back as it was: the extra one isn't sold, and the owner hears it was asked for.
      existing ? existing.restore_attributes : lines.target.delete(line)
      shortage.record
      line.errors.add :base, shortage.message
      return line
    end

    transaction { line.save && recalculate }
    line
  end

  # What a sale wants of one product, more than the branch has free: on hand, less what's held for other customers'
  # orders (`held`, when the shop holds it). `record` notes it for the owner's morning email.
  Shortfall = Data.define(:product, :branch, :needed, :on_hand, :held, :collecting) do
    def initialize(product:, branch:, needed:, on_hand:, held: 0, collecting: nil) = super

    def free = [ on_hand - held, 0 ].max

    def message
      return Product.shortage_message(product, on_hand, branch) unless held.positive? && needed <= on_hand

      orders = product.orders_holding(branch, except: collecting).map(&:reference)
      "Only #{quantity(free)} #{product.name} free at #{branch.name}: #{quantity(held)} #{held == 1 ? "is" : "are"} held for " \
        "#{orders.size == 1 ? "order" : "orders"} #{orders.to_sentence}"
    end

    def record
      branch.account.stock_refusals.create!(branch: branch, product: product, user: Current.user, quantity: needed, on_hand: free)
    end

    private
      def quantity(value) = value.to_d.to_s("F").delete_suffix(".0")
  end

  # Stock can't be sold below zero: what a sale takes of each product (a kit counts as its parts, totalled over every
  # line) must be on the shelf at its branch. Returns the first Shortfall, or nil. `lines` is the sale
  # as it would be; `only:` looks at just the products that one line takes, so a change to one line isn't held up by
  # another. A sale an offline till already made isn't checked: the goods have gone.
  def stock_shortfall(lines = self.lines, only: nil)
    return if offline_uuid.present?

    needed = Hash.new(0)
    products = {}
    lines.each do |line|
      line.stock_items.each do |item, amount|
        needed[item.id] += amount
        products[item.id] = item
      end
    end
    needed.slice!(*only.stock_items.map { _1.first.id }) if only

    needed.each do |id, amount|
      on_hand = products[id].stock_at(branch)
      return Shortfall.new(products[id], branch, amount, on_hand) if amount > on_hand

      # With the shop holding stock for orders, what's promised to other customers isn't free to sell; the order this
      # sale is collecting takes its own.
      next unless account.hold_order_stock?

      held = products[id].reserved_at(branch, except: customer_order)
      return Shortfall.new(products[id], branch, amount, on_hand, held, customer_order) if amount > on_hand - held
    end
    nil
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
