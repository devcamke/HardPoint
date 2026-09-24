class SupplierProduct < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :supplier
  belongs_to :product

  money_attribute :cost

  attr_accessor :product_code

  validates :product, uniqueness: { scope: :supplier_id, message: "is already listed for this supplier" }
  validates :cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :lead_time_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :min_order_quantity, numericality: { greater_than: 0 }
  validates_same_account :supplier, :product
  validate { errors.add :product, "doesn't track stock, so it isn't bought in" if product && !product.track_stock? }

  after_save :make_only_preferred, if: -> { saved_change_to_preferred? && preferred? }

  # Rounds a quantity up to what the supplier will sell (their minimum, in whole multiples).
  def order_quantity_for(needed)
    ((needed / min_order_quantity).ceil * min_order_quantity)
  end

  private
    def make_only_preferred
      product.supplier_products.where.not(id: id).update_all(preferred: false)
    end
end
