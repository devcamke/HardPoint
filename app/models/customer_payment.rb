# A customer paying off what they owe on account. Payments settle the oldest account sales first.
# Cash goes through a till's drawer, so a cash payment belongs to that till's open shift.
class CustomerPayment < ApplicationRecord
  include AccountOwned, Monetary

  METHODS = %w[ cash mobile_money bank_transfer cheque card ].freeze

  belongs_to :customer
  belongs_to :shift, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :amount

  validates :payment_method, inclusion: { in: METHODS }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :paid_on, presence: true
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: -> { payment_method == "mobile_money" }
  validates_same_account :customer, :shift
  validate { errors.add :base, "Cash needs a till with an open shift on this device" if payment_method == "cash" && (shift.nil? || shift.closed?) }

  before_validation { self.paid_on ||= Date.current }
  after_create { customer.track_event "paid", amount: amount_cents, payment_method: payment_method, reference: reference }

  scope :chronologically, -> { order(paid_on: :desc, id: :desc) }
  scope :cash, -> { where(payment_method: "cash") }
end
