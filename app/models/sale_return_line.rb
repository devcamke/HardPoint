class SaleReturnLine < ApplicationRecord
  include AccountOwned

  belongs_to :sale_return, inverse_of: :lines
  belongs_to :sale_line

  validates :quantity, numericality: { greater_than: 0 }
  validates_same_account :sale_line
  validate :from_the_same_sale, :not_more_than_bought, :whole_units

  def calculate_totals
    share = quantity / sale_line.quantity
    sale = sale_line.sale
    cart_factor = sale.subtotal_cents.zero? ? 1 : sale.total_cents.to_r / sale.subtotal_cents
    self.total_cents = (sale_line.total_cents * share * cart_factor).round
    self.tax_cents = (sale_line.tax_cents * share * cart_factor).round
  end

  private
    def from_the_same_sale
      errors.add :sale_line, "isn't on this receipt" if sale_line && sale_return && sale_line.sale_id != sale_return.sale_id
    end

    def not_more_than_bought
      return unless sale_line && quantity

      returnable = sale_line.quantity - sale_line.sale.returned_quantity(sale_line)
      errors.add :base, "Only #{returnable.to_s("F").delete_suffix(".0")} of #{sale_line.product.name} can still be returned" if quantity > returnable
    end

    def whole_units
      errors.add :quantity, "must be a whole number" if sale_line && quantity && !sale_line.product_unit && !sale_line.product.quantity_allowed?(quantity)
    end
end
