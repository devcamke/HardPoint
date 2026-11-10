# Which of the shop's products is one of the calculator's materials, and how many of it one unit of the material is
# (one tonne of sand might be 1,000 of a sand sold by the kg; one litre of paint a twentieth of a 20-litre tin).
class MaterialProduct < ApplicationRecord
  include AccountOwned

  belongs_to :product
  belongs_to :product_unit, optional: true

  validates :material, inclusion: { in: MaterialCalculator::MATERIALS.keys }, uniqueness: { scope: :account_id }
  validates :factor, numericality: { greater_than: 0 }
  validates_same_account :product, :product_unit
  validate { errors.add :product_unit, "must be one of #{product.name}'s packs" if product_unit && product_unit.product_id != product_id }

  # What to put on the quote for this much of the material: rounded up to a whole one for anything sold whole.
  def sell_quantity(quantity)
    amount = quantity.to_d * factor
    whole = product_unit || !product.quantity_allowed?(amount.round(3))
    return amount.ceil if whole

    # Loose goods: a whole kg, metre or litre once there's ten or more, otherwise to the tenth.
    amount >= 10 ? amount.ceil : amount.ceil(1)
  end
end
