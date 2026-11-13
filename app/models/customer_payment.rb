# An entry on a customer's account that isn't a sale: money paid in (a payment), credit handed back to
# them (a refund, kept as a negative amount so every sum stays right), or bad debt the shop has given up
# on (a write-off, which a manager approves with a reason), or what they already owed when the shop moved to
# HardPoint (an opening balance, brought across by the customer import: a debt is a charge, so like a refund
# it's kept negative; credit they had with the shop is positive; a customer has at most one). Payments settle the oldest debts first, the opening balance
# among them, unless they're put against particular sales (allocations). Cash goes through a till's drawer,
# so cash in or out belongs to that till's open shift.
class CustomerPayment < ApplicationRecord
  include AccountOwned, Monetary

  METHODS = %w[ cash mobile_money airtel_money bank_transfer cheque card ].freeze
  KINDS = %w[ payment refund write_off opening_balance ].freeze

  belongs_to :customer
  belongs_to :shift, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  belongs_to :approver, class_name: "User", optional: true
  has_many :allocations, class_name: "CustomerPaymentAllocation", dependent: :destroy, inverse_of: :customer_payment

  money_attribute :amount

  accepts_nested_attributes_for :allocations

  validates :kind, inclusion: { in: KINDS }
  validates :payment_method, inclusion: { in: METHODS }, unless: :without_method?
  validates :payment_method, absence: true, if: :without_method?
  validates :amount_cents, numericality: { greater_than: 0 }, unless: -> { refund? || opening_balance? }
  validates :amount_cents, numericality: { less_than: 0 }, if: :refund?
  validates :amount_cents, numericality: { other_than: 0 }, if: :opening_balance?
  validates :paid_on, presence: true
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: -> { payment_method == "mobile_money" }
  validates :reason, presence: true, if: :write_off?
  validates_same_account :customer, :shift
  validate { errors.add :base, "Cash needs a till with an open shift on this device" if payment_method == "cash" && (shift.nil? || shift.closed?) }
  validate { errors.add :base, "Writing off a debt needs a manager's approval PIN" if write_off? && approver.nil? }
  validate :refund_within_credit, if: :refund?
  validate :only_opening_balance, if: :opening_balance?, on: :create
  validate :allocations_within_amount

  before_validation { self.paid_on ||= Date.current }
  # A refund is entered as the amount handed back; it's kept negative.
  before_validation { self.amount_cents = -amount_cents.abs if refund? && amount_cents }
  after_create :track

  scope :chronologically, -> { order(paid_on: :desc, id: :desc) }
  scope :cash, -> { where(payment_method: "cash") }
  scope :payments, -> { where(kind: "payment") }
  scope :refunds, -> { where(kind: "refund") }
  scope :write_offs, -> { where(kind: "write_off") }
  scope :opening_balances, -> { where(kind: "opening_balance") }
  # Entries that are money changing hands, as opposed to a write-off or an opening balance.
  scope :money, -> { where(kind: %w[ payment refund ]) }

  KINDS.each { |kind| define_method(:"#{kind}?") { self.kind == kind } }

  # An opening balance that is a debt, as opposed to credit the customer had with the shop.
  def opening_debt? = opening_balance? && amount_cents.to_i.negative?

  # What the statement and the customer's page call this entry.
  def description
    case kind
    when "refund" then "Credit refunded, #{payment_method.humanize.downcase}"
    when "write_off" then "Written off: #{reason}"
    when "opening_balance" then opening_debt? ? "Opening balance, brought across" : "Credit brought across"
    else "Payment, #{payment_method.humanize.downcase}"
    end
  end

  private
    def without_method? = write_off? || opening_balance?

    def only_opening_balance
      errors.add :base, "#{customer.name} already has an opening balance" if customer&.customer_payments&.opening_balances&.exists?
    end

    def refund_within_credit
      credit = -customer.balance_cents
      if credit <= 0
        errors.add :base, "#{customer.name} has no credit on their account to refund"
      elsif amount_cents.abs > credit
        errors.add :amount, "is more than the #{Money.format(credit)} credit on the account"
      end
    end

    def allocations_within_amount
      allocated = allocations.sum { _1.amount_cents.to_i }
      return unless allocated.positive?

      errors.add :base, "A refund can't be put against sales" if refund?
      if allocated > amount_cents.to_i
        errors.add :base, "The #{Money.format(allocated)} put against sales is more than the #{Money.format(amount_cents.to_i)} #{write_off? ? "written off" : "paid"}"
      end
    end

    def track
      case kind
      when "refund" then customer.track_event "credit_refunded", amount: amount_cents.abs, payment_method: payment_method, reference: reference
      when "write_off" then customer.track_event "written_off", amount: amount_cents, approver: approver, reason: reason
      when "opening_balance" then customer.track_event "opening_balance_set", amount: amount_cents.abs, credit: (true unless opening_debt?), as_of: paid_on
      else customer.track_event "paid", amount: amount_cents, payment_method: payment_method, reference: reference
      end
    end
end
