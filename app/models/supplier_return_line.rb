class SupplierReturnLine < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :supplier_return, inverse_of: :lines
  belongs_to :product
  belongs_to :stock_batch, optional: true

  attr_reader :product_code

  money_attribute :unit_cost, :total, :tax

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :product, :stock_batch
  validate { errors.add :base, "No product with barcode or SKU “#{product_code}”" if product_code.present? && product.nil? }
  validate { errors.add :base, "#{product.name} doesn't track stock" if product && !product.track_stock? }
  validate { errors.add :quantity, "of #{product.name} must be a whole number" if product && quantity && !product.quantity_allowed?(quantity) }
  validate :on_hand_to_send
  validate :batch_is_this_products

  before_validation { self.unit_cost_cents = default_unit_cost if unit_cost_cents.nil? && product }
  before_validation { self.tax_rate = product.effective_tax_rate&.rate || 0 if product && tax_rate.to_d.zero? }

  def product_code=(code)
    @product_code = code
    self.product = Current.account.products.find_by_code(code) if code.present?
  end

  # Costs are kept ex VAT; the debit note charges back VAT on top, as the supplier invoiced it.
  def calculate_totals
    net = (unit_cost_cents * quantity.to_d).round
    self.tax_cents = (net * tax_rate.to_d / 100).round
    self.total_cents = net + tax_cents
  end

  private
    # What the shop paid: the delivery it came in on, else this supplier's last price, else the product's cost.
    def default_unit_cost
      receipt = supplier_return&.goods_receipt
      received = receipt&.lines&.find { _1.product_id == product.id }
      return received.unit_cost_cents if received

      supplier_cost = supplier_return&.supplier&.supplier_products&.find_by(product: product)&.cost_cents
      return supplier_cost if supplier_cost.to_i.positive?

      rate = supplier_return&.exchange_rate
      rate ? (product.cost_cents / rate.to_d).ceil : product.cost_cents
    end

    def on_hand_to_send
      return unless product && quantity && supplier_return&.branch
      available = stock_batch ? stock_batch.quantity : product.stock_at(supplier_return.branch)
      errors.add :quantity, "of #{product.name} is more than the #{available.to_s("F").delete_suffix(".0")} in stock#{" in that batch" if stock_batch}" if quantity > available
    end

    def batch_is_this_products
      return unless stock_batch && product
      errors.add :stock_batch, "isn't #{product.name}'s at this branch" if stock_batch.product_id != product.id || stock_batch.branch_id != supplier_return&.branch_id
    end
end
