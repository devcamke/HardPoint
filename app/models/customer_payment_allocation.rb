# Part of a payment (or write-off) put against one particular account sale, rather than left to settle
# the oldest first. The customer's balance is still the whole ledger; an allocation only decides which
# invoice counts as settled, so a disputed invoice can stay open while later ones are paid.
class CustomerPaymentAllocation < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :customer_payment
  belongs_to :sale

  money_attribute :amount

  validates :amount_cents, numericality: { greater_than: 0 }
  validates_same_account :sale
  validate :sale_is_an_open_account_sale, on: :create

  private
    def sale_is_an_open_account_sale
      return if sale.nil? || customer_payment&.customer.nil?

      open = customer_payment.customer.open_invoices.find { _1.sale == sale }
      if open.nil?
        errors.add :sale, "#{sale.receipt_number || sale.id} isn't an unpaid account sale of #{customer_payment.customer.name}"
      elsif amount_cents.to_i > open.outstanding_cents
        errors.add :base, "only #{Money.format(open.outstanding_cents)} is owed on #{sale.receipt_number}"
      end
    end
end
