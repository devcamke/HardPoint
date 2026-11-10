# One line of a fundi's commission ledger. Never changed or removed: a void or return is an entry of its own.
#   earned   — a completed sale they brought (positive)
#   reversed — that sale voided, or some of it returned (negative)
#   paid     — commission paid out to them (negative)
# sales_cents is the value before tax the entry was worked on, for "brought in" figures.
class FundiEntry < ApplicationRecord
  include AccountOwned

  KINDS = %w[ earned reversed paid ].freeze

  belongs_to :fundi
  belongs_to :source, polymorphic: true
  belongs_to :creator, class_name: "User", optional: true, default: -> { Current.user }

  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { other_than: 0 }
  validates_same_account :fundi

  scope :chronologically, -> { order(:created_at, :id) }

  def readonly?
    persisted?
  end

  # What a sale earns the fundi who brought it: each line's value before tax at that line's rate.
  def self.commission_for(sale)
    sale.lines.includes(product: { category: :parent }).sum do |line|
      net = line.total_cents - line.tax_cents
      (net * sale.fundi.commission_percent_for(line.product) / 100).round
    end
  end
end
