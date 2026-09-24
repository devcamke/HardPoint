# One attempt to pay an invoice: an M-Pesa prompt or a Paystack card checkout. Each attempt has a
# unique reference, so a provider telling us twice pays the invoice once.
class Billing::Payment < ApplicationRecord
  include AccountOwned, Monetary

  PROVIDERS = %w[ mpesa paystack manual ].freeze

  belongs_to :invoice
  belongs_to :user, default: -> { Current.user }, optional: true

  enum :status, %w[ pending succeeded failed ].index_by(&:itself), default: :pending

  money_attribute :amount

  validates :provider, inclusion: { in: PROVIDERS }
  validates :reference, presence: true, uniqueness: true

  def succeed(receipt: nil, amount_cents: self.amount_cents)
    with_lock do
      return false unless pending?

      if amount_cents.to_i < invoice.amount_cents
        update!(status: :failed, failure: "Paid #{Money.format(amount_cents, currency: invoice.currency)}, less than the invoice", completed_at: Time.current)
        return false
      end
      update!(status: :succeeded, receipt: receipt, completed_at: Time.current)
    end
    invoice.mark_paid(self)
    account.track_event "subscription_paid", creator: user, invoice: invoice.number, provider: provider, receipt: receipt
    true
  end

  def fail(reason)
    pending? && update!(status: :failed, failure: reason.to_s.first(250), completed_at: Time.current)
  end
end
