class SaleLine < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :sale, inverse_of: :lines
  belongs_to :product
  belongs_to :product_unit, optional: true
  belongs_to :promotion, optional: true

  money_attribute :unit_price, :discount, :total, :tax, :promotion_discount

  validates :quantity, numericality: { greater_than: 0 }
  validates :discount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :sale, :product, :product_unit
  validate :whole_units, :one_per_serial_number, :discount_within_price

  before_validation(on: :create) { self.tax_rate = product.effective_tax_rate&.rate || 0 }
  before_save :calculate_totals

  def unit
    product_unit&.unit || product.unit
  end

  # How many of the product's base unit this line takes out of stock.
  def base_quantity
    quantity * (product_unit&.quantity || 1)
  end

  def gross_cents
    (unit_price_cents * quantity).round
  end

  def discount_percent
    gross_cents.positive? ? discount_cents * 100.0 / gross_cents : 0
  end

  # Lines from a customer order keep the price the customer was quoted.
  def reprice
    return if customer_order_line_id
    self.unit_price_cents = product_unit ? product_unit.effective_price_cents : product.price_cents_for(quantity: quantity, price_list: sale.price_list)
    apply_best_promotion
  end

  # The running promotion that saves the customer most on this line, if any.
  def apply_best_promotion
    best = sale.running_promotions.map { [ _1, _1.saving_cents(product: product, quantity: quantity, unit_price_cents: unit_price_cents, product_unit: product_unit) ] }
      .select { _2.positive? }.max_by(&:last)
    self.promotion, self.promotion_discount_cents = best || [ nil, 0 ]
  end

  def description
    name = product_unit ? "#{product.name} (#{product_unit})" : product.name
    detail.present? ? "#{name} · #{detail}" : name
  end

  # Recorded when the sale completes, so margins stay true after costs change.
  def deduct_stock
    update_columns cost_cents: current_cost_cents
    stock_items.each do |item, amount|
      item.move_stock(branch: sale.branch, quantity: -amount, reason: "sold", source: sale, creator: sale.cashier)
    end
  end

  # Batch-tracked stock goes back into the batches the sale took it from.
  def restore_stock(quantity = self.quantity, reason: "returned", source: sale)
    share = quantity / self.quantity
    stock_items.each do |item, amount|
      item.move_stock(branch: sale.branch, quantity: amount * share, reason: reason, source: source,
        reverses: { taken_by: [ sale ], returned_by: [ sale, *sale.sale_returns ] })
    end
  end

  def stock_on_hand
    product.stock_at(sale.branch) / (product_unit&.quantity || 1)
  end

  # What the line costs the shop at today's weighted-average cost, ex tax. Kits cost their parts.
  def current_cost_cents
    if product.kit?
      product.kit_components.includes(:component).sum { |part| part.component.cost_cents * part.quantity * base_quantity }.round
    else
      (product.cost_cents * base_quantity).round
    end
  end

  private
    # Kits take their components out of stock; untracked products (services) take nothing.
    def stock_items
      if product.kit?
        product.kit_components.includes(:component).select { _1.component.track_stock? }.map { [ _1.component, _1.quantity * base_quantity ] }
      elsif product.track_stock?
        [ [ product, base_quantity ] ]
      else
        []
      end
    end

    def calculate_totals
      self.total_cents = gross_cents - discount_cents - promotion_discount_cents.to_i
      self.tax_cents = (total_cents * tax_rate / (100 + tax_rate)).round
    end

    def whole_units
      if quantity && !(product_unit ? quantity.frac.zero? : product.quantity_allowed?(quantity))
        errors.add :quantity, "must be a whole number of #{unit.name.pluralize.downcase}"
      end
    end

    def one_per_serial_number
      errors.add :quantity, "must be 1 for items with a serial number" if product&.serialized? && quantity != 1
    end

    def discount_within_price
      errors.add :discount, "can't be more than the line's price" if discount_cents.to_i + promotion_discount_cents.to_i > gross_cents
    end
end
