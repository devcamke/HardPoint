class StockCountLine < ApplicationRecord
  include AccountOwned

  belongs_to :stock_count
  belongs_to :product

  validates :counted_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add :counted_quantity, "must be a whole number" if counted_quantity && !product.quantity_allowed?(counted_quantity) }

  scope :counted, -> { where.not(counted_quantity: nil) }
  scope :uncounted, -> { where(counted_quantity: nil) }
  scope :with_variance, -> { counted.where("counted_quantity <> expected_quantity") }

  def variance
    counted_quantity ? counted_quantity - expected_quantity : 0
  end
end
