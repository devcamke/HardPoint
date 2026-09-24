# What the platform keeps once a shop is deleted: who it was, who asked, and the invoices HardPoint
# issued it (tax law requires keeping those). None of the shop's own records.
class AccountDeletion < ApplicationRecord
  def self.record(account)
    create!(former_account_id: account.id, name: account.name, subdomain: account.subdomain,
      requested_by_email: account.deletion_requested_by&.email_address, requested_at: account.deletion_scheduled_for&.-(Account::Closure::GRACE),
      billing_invoices: account.billing_invoices.map { |invoice|
        invoice.slice(:number, :plan, :period_start, :period_end, :amount_cents, :currency, :status, :paid_at)
      })
  end
end
