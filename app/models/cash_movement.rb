# Cash in or out of the drawer that isn't a sale: dropping takings to the safe, paying a
# supplier or buying lunch from the till (payout), or topping up change (pay in).
class CashMovement < ApplicationRecord
  include AccountOwned, Monetary

  KINDS = %w[ drop payout pay_in ].freeze

  belongs_to :shift
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :amount

  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :reason, presence: true
  validates_same_account :shift
  validate { errors.add :shift, "is closed" if shift&.closed? }

  def outgoing?
    kind.in?(%w[ drop payout ])
  end
end
