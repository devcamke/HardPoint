class Payment < ApplicationRecord
  include AccountOwned, Monetary

  TENDERS = %w[ cash card mobile_money on_account deposit foreign_cash ].freeze

  belongs_to :sale

  enum :tender, TENDERS.index_by(&:itself)

  money_attribute :amount, :tendered

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :tendered_cents, numericality: { greater_than_or_equal_to: :amount_cents }, if: -> { cash? || foreign_cash? }
  validates :currency, :foreign_tendered_cents, :exchange_rate, presence: true, if: :foreign_cash?
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: :mobile_money?
  validates_same_account :sale

  # A code typed at the till for money that already arrived on the Paybill claims it.
  after_create_commit :claim_mpesa_transaction, if: -> { mobile_money? && reference.present? }

  # Change is always given in the shop's own currency, foreign notes included.
  def change_cents
    cash? || foreign_cash? ? tendered_cents - amount_cents : 0
  end

  def label
    if deposit? then "Deposit used"
    elsif foreign_cash? then "#{Money.format(foreign_tendered_cents, currency: currency)} cash @ #{exchange_rate.to_d.round(4).to_s("F")}"
    else tender.humanize
    end
  end

  private
    def claim_mpesa_transaction
      sale.account.mpesa_transactions.unmatched.find_by(trans_id: reference.strip.upcase)&.match(self)
    end
end
