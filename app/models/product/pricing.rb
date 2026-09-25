module Product::Pricing
  extend ActiveSupport::Concern

  # The unit price for a customer: the lowest of the retail price, retail quantity breaks and,
  # when they're on one, their price list's prices, among those that apply at this quantity.
  def price_cents_for(quantity: 1, price_list: nil)
    applicable = price_list_items.select do |item|
      (item.price_list_id.nil? || item.price_list_id == price_list&.id) && item.min_quantity <= quantity.to_d
    end

    [ price_cents, *applicable.map(&:price_cents) ].min
  end

  # The best percentage-off promotion running today, and the price with it, for quotes, online orders
  # and the store's shelves: [ promotion, price ], or nil. With no branch, only promotions that run
  # at every branch count (the store shows those).
  def promotion_price(branch: nil, product_unit: nil, unit_price_cents: product_unit ? product_unit.effective_price_cents : price_cents)
    offers = account.running_promotions.select { _1.percent_off? && _1.covers?(self) && (branch ? _1.available_at?(branch) : _1.branch_ids.empty?) }
      .map { [ _1, _1.price_cents_for(self, unit_price_cents, product_unit: product_unit) ] }
    best = offers.min_by(&:last)
    best if best && best.last < unit_price_cents
  end

  def effective_tax_rate
    tax_rate || account.tax_rates.find_by(default: true)
  end

  # Costs are kept ex tax, so the margin is on the price ex tax.
  def margin_percent
    return if price_cents.to_i.zero?

    price_ex_tax = price_cents * 100 / (100 + (effective_tax_rate&.rate || 0))
    ((price_ex_tax - cost_cents) * 100.0 / price_ex_tax).round(1)
  end
end
