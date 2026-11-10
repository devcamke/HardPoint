class Payment < ApplicationRecord
  include AccountOwned, Monetary, MobileMoneyCode

  # "points": loyalty points, which HardPoint no longer has. Payments made with them are kept, as is their eTIMS code.
  TENDERS = %w[ cash card mobile_money airtel_money on_account deposit foreign_cash points ].freeze

  belongs_to :sale

  enum :tender, TENDERS.index_by(&:itself)

  money_attribute :amount, :tendered

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :tendered_cents, numericality: { greater_than_or_equal_to: :amount_cents }, if: -> { cash? || foreign_cash? || mobile_money? || airtel_money? }
  validates :currency, :foreign_tendered_cents, :exchange_rate, presence: true, if: :foreign_cash?
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: :mobile_money?
  validates :reference, presence: { message: "is needed (the Airtel Money transaction ID)" }, if: :airtel_money?
  validates_same_account :sale

  # Money that arrived by phone stays usable when the payment it paid is taken off the sale.
  before_destroy :release_mobile_money

  # Change is always given in the shop's own currency, foreign notes included. A customer who sends more by
  # M-Pesa or Airtel Money than was due gets the difference back in cash, so that's change too.
  def change_cents
    cash? || foreign_cash? || mobile_money? || airtel_money? ? tendered_cents.to_i - amount_cents : 0
  end

  def label
    if deposit? then "Deposit used"
    elsif points? then "#{points} points"
    elsif airtel_money? then "Airtel Money"
    elsif foreign_cash? then "#{Money.format(foreign_tendered_cents, currency: currency)} cash @ #{exchange_rate.to_d.round(4).to_s("F")}"
    else tender.humanize
    end
  end

  private
    # A code typed at the till (MobileMoneyCode): the customer must have sent at least what was tendered.
    def mobile_money_code?
      mobile_money?
    end

    def mobile_money_cents
      tendered_cents || amount_cents
    end

    def release_mobile_money
      sale.account.mpesa_transactions.where(matched: self).update_all(matched_id: nil, matched_type: nil, matched_at: nil)
      Mpesa::StkRequest.where(payment: self).update_all(payment_id: nil)
      Airtel::Request.where(payment: self).update_all(payment_id: nil)
    end
end
