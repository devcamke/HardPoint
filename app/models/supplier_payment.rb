class SupplierPayment < ApplicationRecord
  include AccountOwned, Monetary

  METHODS = %w[ bank_transfer mobile_money cheque cash ].freeze

  belongs_to :supplier
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  money_attribute :amount

  validates :payment_method, inclusion: { in: METHODS }
  validates :amount_cents, numericality: { greater_than: 0 }
  validates :paid_on, presence: true
  validates_same_account :supplier

  after_create { supplier.track_event "paid", amount: amount_cents, payment_method: payment_method, reference: reference }

  scope :chronologically, -> { order(paid_on: :desc, id: :desc) }
end
