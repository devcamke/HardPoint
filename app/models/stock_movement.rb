# One line of the stock ledger. Movements are never changed or removed; corrections are new movements.
class StockMovement < ApplicationRecord
  include AccountOwned

  REASONS = %w[ opening received sold returned found damaged stolen expired internal_use correction
                transfer_out transfer_in transfer_returned count ].freeze

  belongs_to :branch
  belongs_to :product
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :creator, class_name: "User", optional: true

  validates :reason, inclusion: { in: REASONS }
  validates :quantity, numericality: { other_than: 0 }
  validates_same_account :branch, :product

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def readonly?
    persisted?
  end
end
