# A pack size the product is also sold in: e.g. a box of 100 screws is 100 pieces.
class ProductUnit < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :product
  belongs_to :unit
  has_many :barcodes, dependent: :destroy

  money_attribute :price

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit, uniqueness: { scope: :product_id, message: "already has a pack size for this product" }
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates_same_account :product, :unit
  validate { errors.add :unit, "can't be the product's own unit" if unit_id.present? && unit_id == product&.unit_id }

  # Without its own price, a pack costs the same as its pieces bought one by one.
  def effective_price_cents
    price_cents || (product.price_cents * quantity).round
  end

  def to_s
    "#{unit.name} of #{quantity.to_s("F").delete_suffix(".0")} #{product.unit.abbreviation}"
  end
end
