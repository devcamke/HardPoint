module Product::Purchasing
  extend ActiveSupport::Concern

  included do
    has_many :supplier_products, dependent: :destroy
    has_many :suppliers, through: :supplier_products
  end

  def preferred_supplier_product
    supplier_products.includes(:supplier).max_by { [ _1.preferred? ? 1 : 0, -_1.cost_cents ] }
  end

  # Goods arriving: the product's cost becomes the weighted average of the stock already held
  # (at the old cost) and the new stock (at its landed cost). With nothing on hand, the new cost wins.
  def receive_into_stock(branch:, quantity:, unit_cost_cents:, source:)
    with_lock do
      on_hand = stock_on_hand
      average = if on_hand.positive?
        ((on_hand * cost_cents + quantity * unit_cost_cents) / (on_hand + quantity)).round
      else
        unit_cost_cents
      end

      update!(cost_cents: average) if average != cost_cents
      move_stock(branch: branch, quantity: quantity, reason: "received", source: source, unit_cost_cents: unit_cost_cents)
    end
  end
end
