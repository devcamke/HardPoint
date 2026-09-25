# One manufacturer's batch of a product at a branch, with its expiry date and how much is left.
# Batches are filled by deliveries, and emptied first-expiring-first by sales and other stock out.
class StockBatch < ApplicationRecord
  include AccountOwned

  EXPIRING_WITHIN = 30.days

  belongs_to :branch
  belongs_to :product
  has_many :stock_movements, dependent: :restrict_with_error

  normalizes :number, with: ->(number) { number.squish.upcase }

  validates :number, presence: true, length: { maximum: 40 }
  validates_same_account :branch, :product

  scope :in_stock, -> { where("stock_batches.quantity > 0") }
  scope :by_expiry, -> { order(Arel.sql("stock_batches.expires_on ASC NULLS LAST"), :created_at, :id) }
  scope :expired, ->(on = Date.current) { where(expires_on: ...on) }
  scope :expiring, ->(on = Date.current, within: EXPIRING_WITHIN) { where(expires_on: on..(on + within)) }

  def name
    "#{product.name} batch #{number}"
  end

  def expired?(on = Date.current)
    expires_on.present? && expires_on < on
  end

  def expiring?(on = Date.current)
    expires_on.present? && !expired?(on) && expires_on <= on + EXPIRING_WITHIN
  end

  def value_cents
    (quantity * product.cost_cents).round
  end

  # For a recall: every sale that took stock from this batch, whichever branch it was at.
  def sales
    Sale.where(id: StockMovement.joins(:stock_batch)
      .where(stock_batches: { product_id: product_id, number: number }, reason: "sold", source_type: "Sale").select(:source_id))
  end

  # Takes stock out of this batch on purpose (expired, damaged), rather than first-expiring-first.
  def write_off(quantity, reason:, note: nil, creator: Current.user)
    quantity = quantity.to_d
    raise ArgumentError, "Choose between 0 and #{self.quantity.to_s("F")}" unless quantity.positive? && quantity <= self.quantity

    product.move_stock(branch: branch, quantity: -quantity, reason: reason, note: note, batch: self, creator: creator)
  end
end
