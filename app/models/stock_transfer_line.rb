class StockTransferLine < ApplicationRecord
  include AccountOwned

  belongs_to :stock_transfer, inverse_of: :lines
  belongs_to :product

  attr_reader :product_code

  validates :quantity, numericality: { greater_than: 0 }
  validates_same_account :product
  validate :product_found, :whole_units, :enough_stock, on: :create

  # Lines are entered by scanning or typing a barcode or SKU.
  def product_code=(code)
    @product_code = code
    self.product = Current.account.products.find_by_code(code) if code.present?
  end

  private
    def product_found
      errors.add :base, "No product with barcode or SKU “#{product_code}”" if product_code.present? && product.nil?
    end

    def whole_units
      errors.add :quantity, "for #{product.name} must be a whole number" if product && quantity && !product.quantity_allowed?(quantity)
    end

    def enough_stock
      branch = stock_transfer&.from_branch
      return unless product && branch && quantity

      if !product.track_stock?
        errors.add :base, "#{product.name} doesn't track stock"
      elsif product.stock_at(branch) < quantity
        errors.add :base, "Only #{product.stock_at(branch).to_s("F").delete_suffix(".0")} #{product.name} at #{branch.name}"
      end
    end
end
