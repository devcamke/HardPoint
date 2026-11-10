# Cash in or out of the drawer that isn't a sale: dropping takings to the safe, paying a
# supplier or buying lunch from the till (payout), or topping up change (pay in).
class CashMovement < ApplicationRecord
  include AccountOwned, Monetary

  KINDS = %w[ drop payout pay_in ].freeze

  belongs_to :shift
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  # A payout that paid a supplier's bill is also a cash payment to the supplier, so it comes off
  # what the shop owes them, and the profit and loss leaves it out of expenses: the goods it paid
  # for are counted as they're sold.
  belongs_to :supplier_payment, optional: true

  attr_accessor :supplier_id

  money_attribute :amount

  validates :kind, inclusion: { in: KINDS }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :reason, presence: true
  validates_same_account :shift
  validate { errors.add :shift, "is closed" if shift&.closed? }
  validate :supplier_paid_by_payout, if: -> { supplier_id.present? }

  before_create :pay_supplier, if: -> { supplier_id.present? }

  def outgoing?
    kind.in?(%w[ drop payout ])
  end

  # Payouts above the shop's limit need an owner's or manager's say-so; drops to the safe and pay-ins don't.
  def needs_approval?
    kind == "payout" && amount_cents.to_i > account.payout_approval_above_cents
  end

  def supplier
    (account || Current.account).suppliers.find_by(id: supplier_id) if supplier_id.present?
  end

  private
    def supplier_paid_by_payout
      errors.add :supplier_id, "can be paid only by a payout" unless kind == "payout"
      errors.add :supplier_id, "isn't one of this shop's suppliers" unless supplier
    end

    def pay_supplier
      self.supplier_payment = account.supplier_payments.create!(supplier: supplier, amount_cents: amount_cents, payment_method: "cash",
        paid_on: Date.current, note: reason)
    end
end
