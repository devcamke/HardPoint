# One batch of a batch-tracked product in a stock take: a batch in stock when the count started,
# stock not in any batch (number nil), or a batch found on the shelf that the system didn't have.
# Counting a batch updates the product's line, so totals, progress and differences work as for
# any product; approving corrects each batch on its own.
class StockCountBatch < ApplicationRecord
  include AccountOwned

  belongs_to :stock_count_line
  belongs_to :stock_batch, optional: true

  normalizes :number, with: ->(number) { number.squish.upcase.presence }

  validates :counted_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add :counted_quantity, "must be a whole number" if counted_quantity && !stock_count_line.product.quantity_allowed?(counted_quantity) }
  validates_same_account :stock_count_line, :stock_batch

  scope :counted, -> { where.not(counted_quantity: nil) }
  scope :in_order, -> { order(Arel.sql("stock_count_batches.number IS NULL"), Arel.sql("stock_count_batches.expires_on ASC NULLS LAST"), :number) }

  after_save { stock_count_line.total_up_batches }

  def label
    number ? "Batch #{number}" : "Not in a batch"
  end

  # Found on the shelf rather than expected.
  def found?
    number.present? && expected_quantity.zero?
  end

  def variance
    counted_quantity ? counted_quantity - expected_quantity : 0
  end

  # Corrects the batch to what was counted. A batch sold from during the count can't go below
  # nothing; what's left to take comes from the product's other stock, as a sale would.
  def post_variance(count, user)
    product = stock_count_line.product
    return if variance.zero?

    if number.nil?
      product.move_stock(branch: count.branch, quantity: variance, reason: "count", source: count, creator: user, batch: nil)
    elsif variance.positive?
      product.move_stock(branch: count.branch, quantity: variance, reason: "count", source: count, creator: user,
        batch: stock_batch || { number: number, expires_on: expires_on })
    else
      from_batch = [ -variance, stock_batch.reload.quantity ].min
      product.move_stock(branch: count.branch, quantity: -from_batch, reason: "count", source: count, creator: user, batch: stock_batch) if from_batch.positive?
      product.move_stock(branch: count.branch, quantity: variance + from_batch, reason: "count", source: count, creator: user) if -variance > from_batch
    end
  end
end
