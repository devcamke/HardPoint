class PurchaseOrderLine < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :purchase_order, inverse_of: :lines
  belongs_to :product

  attr_reader :product_code

  money_attribute :unit_cost

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :product
  validate { errors.add :base, "No product with barcode or SKU “#{product_code}”" if product_code.present? && product.nil? }
  validate { errors.add :base, "#{product.name} doesn't track stock, so it can't be ordered" if product && !product.track_stock? }
  validate { errors.add :quantity, "of #{product.name} must be a whole number" if product && quantity && !product.quantity_allowed?(quantity) }

  before_validation :default_unit_cost, if: -> { unit_cost_cents.blank? || unit_cost_cents.zero? }

  # Lines are entered by scanning or typing a barcode or SKU.
  def product_code=(code)
    @product_code = code
    self.product = Current.account.products.find_by_code(code) if code.present?
  end

  def outstanding_quantity
    quantity - received_quantity
  end

  def line_total_cents
    (unit_cost_cents.to_i * quantity.to_d).round
  end

  def supplier_product
    product && purchase_order&.supplier && product.supplier_products.find_by(supplier: purchase_order.supplier)
  end

  private
    # The supplier's price for it, else what the shop last paid.
    def default_unit_cost
      self.unit_cost_cents = supplier_product&.cost_cents.to_i.nonzero? || product&.cost_cents || 0
    end
end
