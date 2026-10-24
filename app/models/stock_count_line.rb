# A product in a stock take: what was expected when it started and what was counted. Batch-tracked
# products are counted by batch (StockCountBatch) and their line totals the batches.
class StockCountLine < ApplicationRecord
  include AccountOwned

  belongs_to :stock_count
  belongs_to :product
  has_many :batch_counts, class_name: "StockCountBatch", dependent: :delete_all

  validates :counted_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add :counted_quantity, "must be a whole number" if counted_quantity && !product.quantity_allowed?(counted_quantity) }

  scope :counted, -> { where.not(counted_quantity: nil) }
  scope :uncounted, -> { where(counted_quantity: nil) }
  scope :with_variance, -> { counted.where("counted_quantity <> expected_quantity") }

  def variance
    counted_quantity ? counted_quantity - expected_quantity : 0
  end

  def by_batch?
    batch_counts.loaded? ? batch_counts.any? : batch_counts.exists?
  end

  # Counts a batch, found by number (blank for stock not in a batch); a batch the take didn't
  # expect is added. "add" suits counting a batch in several places; "set" corrects it.
  def count_batch(number:, quantity:, mode: "set", expires_on: nil)
    with_lock do
      row = batch_counts.find_or_initialize_by(number: StockCountBatch.normalize_value_for(:number, number.to_s)) do |found|
        found.account = account
        found.stock_batch = product.stock_batches.find_by(branch: stock_count.branch, number: found.number) if found.number
        found.expires_on = expires_on.presence || found.stock_batch&.expires_on
      end
      row.counted_quantity = mode == "add" ? row.counted_quantity.to_d + quantity.to_d : quantity
      row.save
      row
    end
  end

  # The batches' differences, on top of what was expected; uncounted batches are left as they are.
  def total_up_batches
    counted = batch_counts.counted
    update_columns counted_quantity: (expected_quantity + counted.sum(&:variance) if counted.any?), updated_at: Time.current
  end
end
