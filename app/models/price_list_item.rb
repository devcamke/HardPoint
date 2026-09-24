class PriceListItem < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :price_list, optional: true
  belongs_to :product

  money_attribute :price

  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :min_quantity, numericality: { greater_than: 0 }
  validates :min_quantity, uniqueness: { scope: %i[ product_id price_list_id ], message: "already has a price" }
  validates_same_account :price_list, :product

  def label
    price_list ? price_list.name : "Retail"
  end
end
