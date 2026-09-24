class Barcode < ApplicationRecord
  include AccountOwned

  belongs_to :product
  belongs_to :product_unit, optional: true

  normalizes :code, with: ->(code) { code.strip }

  validates :code, presence: true, uniqueness: { scope: :account_id, message: "is already used by another product" },
    format: { with: /\A[\x20-\x7E]{1,48}\z/, message: "can only use printable characters" }
  validates_same_account :product, :product_unit
  validate { errors.add :product_unit, "must be one of this product's pack sizes" if product_unit && product_unit.product_id != product_id }

  def internal?
    code == Product.internal_barcode_for(product_id)
  end

  def ean13?
    code.match?(/\A\d{13}\z/) && Product.ean13_check_digit(code[0, 12]) == code[-1].to_i
  end
end
