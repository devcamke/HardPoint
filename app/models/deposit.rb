# Money paid towards a customer order before collection; negative when it's refunded. Cash goes
# through a till's drawer, so a cash deposit belongs to that till's open shift.
class Deposit < ApplicationRecord
  include AccountOwned, Monetary

  TENDERS = %w[ cash mobile_money card bank_transfer ].freeze

  belongs_to :customer_order
  belongs_to :shift, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :amount

  validates :tender, inclusion: { in: TENDERS }
  validates :amount_cents, numericality: { other_than: 0 }
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: -> { tender == "mobile_money" }
  validates_same_account :customer_order, :shift
  validate { errors.add :base, "Cash needs a till with an open shift on this device" if tender == "cash" && (shift.nil? || shift.closed?) }

  scope :cash, -> { where(tender: "cash") }

  def refund?
    amount_cents.negative?
  end
end
