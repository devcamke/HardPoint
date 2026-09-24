class Payment < ApplicationRecord
  include AccountOwned, Monetary

  TENDERS = %w[ cash card mobile_money on_account deposit ].freeze

  belongs_to :sale

  enum :tender, TENDERS.index_by(&:itself)

  money_attribute :amount, :tendered

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :tendered_cents, numericality: { greater_than_or_equal_to: :amount_cents }, if: :cash?
  validates :reference, presence: { message: "is needed (the M-Pesa or other transaction code)" }, if: :mobile_money?
  validates_same_account :sale

  # A code typed at the till for money that already arrived on the Paybill claims it.
  after_create_commit :claim_mpesa_transaction, if: -> { mobile_money? && reference.present? }

  def change_cents
    cash? ? tendered_cents - amount_cents : 0
  end

  def label
    deposit? ? "Deposit used" : tender.humanize
  end

  private
    def claim_mpesa_transaction
      sale.account.mpesa_transactions.unmatched.find_by(trans_id: reference.strip.upcase)&.match(self)
    end
end
