# The till turned a sale away because the stock wasn't on the shelf. Never shown to the cashier again; the owner reads
# them in the morning email as what would have sold with the delivery in. Quantities are in the product's base unit.
class StockRefusal < ApplicationRecord
  include AccountOwned

  belongs_to :branch
  belongs_to :product
  belongs_to :user, optional: true

  validates_same_account :branch, :product

  # Product → [ times turned away, quantity asked for ], most-asked first.
  def self.by_product
    group(:product_id).pluck(:product_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(quantity)"))
      .sort_by { -_2 }
  end
end
