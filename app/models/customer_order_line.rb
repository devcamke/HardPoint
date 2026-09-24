class CustomerOrderLine < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :customer_order, inverse_of: :lines
  belongs_to :product
  belongs_to :product_unit, optional: true

  attr_reader :product_code

  money_attribute :unit_price, :total, :tax

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :product, :product_unit
  validate { errors.add :base, "No product with barcode or SKU “#{product_code}”" if product_code.present? && product.nil? }
  validate { errors.add :quantity, "of #{product.name} must be a whole number" if product && quantity && !product_unit && !product.quantity_allowed?(quantity) }

  before_validation :default_price_and_tax, if: :new_record?

  # Lines are entered by scanning or typing a barcode or SKU; a pack's barcode orders the pack.
  def product_code=(code)
    @product_code = code
    return if code.blank?

    barcode = Current.account.barcodes.find_by(code: code.strip)
    self.product_unit = barcode&.product_unit
    self.product = barcode&.product || Current.account.products.find_by_code(code)
  end

  def description
    product_unit ? "#{product.name} (#{product_unit})" : product.name
  end

  def unit
    product_unit&.unit || product.unit
  end

  def calculate_totals
    self.total_cents = (unit_price_cents.to_i * quantity.to_d).round
    self.tax_cents = (total_cents * tax_rate / (100 + tax_rate)).round
  end

  private
    def default_price_and_tax
      return unless product

      self.tax_rate = product.effective_tax_rate&.rate || 0
      if unit_price_cents.to_i.zero?
        self.unit_price_cents = product_unit ? product_unit.effective_price_cents :
          product.price_cents_for(quantity: quantity || 1, price_list: customer_order&.price_list)
      end
    end
end
