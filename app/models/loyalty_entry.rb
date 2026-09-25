# One change to a customer's points. Entries are never edited: a void or return adds a reversal,
# a manager's correction is an adjustment with a note, so every balance can be explained.
class LoyaltyEntry < ApplicationRecord
  include AccountOwned

  KINDS = %w[ earned redeemed reversed adjusted ].freeze

  belongs_to :customer
  belongs_to :sale, optional: true
  belongs_to :payment, optional: true
  belongs_to :sale_return, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :points, numericality: { other_than: 0, only_integer: true }
  validates :note, presence: true, if: -> { kind == "adjusted" }
  validates_same_account :customer, :sale, :payment, :sale_return

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def description
    case kind
    when "earned" then "Earned on #{sale&.receipt_number}"
    when "redeemed" then "Spent on #{sale&.receipt_number || "a sale"}"
    when "reversed" then sale_return ? "Return #{sale_return.return_number}" : "Sale #{sale&.receipt_number} voided"
    else "Adjusted: #{note}"
    end
  end
end
