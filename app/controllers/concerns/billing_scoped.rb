# The Billing pages: for owners, and open even while the shop is read-only, since that's where it's paid.
module BillingScoped
  extend ActiveSupport::Concern

  included do
    allow_while_locked
    before_action :ensure_can_manage_account
  end

  private
    # After a change of plan or add-ons that billed the rest of the period at once.
    def rest_of_period_notice(account)
      invoice = account.rest_of_period_invoice or return
      "Invoice #{invoice.number} for #{Money.format(invoice.amount_cents)} covers the rest of this period. "
    end

    def open_invoice
      Current.account.open_invoice or redirect_to(billing_path, alert: "Nothing is due right now.") && nil
    end
end
