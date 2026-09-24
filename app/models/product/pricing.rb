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
