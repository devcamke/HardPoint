class StockLevel < ApplicationRecord
  include AccountOwned

  belongs_to :branch
  belongs_to :product

  validates_same_account :branch, :product
end
