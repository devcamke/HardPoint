# What a customer owes on account. A sale put (partly) on account is the invoice, due after the
# customer's payment terms. Payments and returns credited to the account settle the oldest
# invoices first (FIFO), which is what the ageing report and statements are based on.
module Customer::Receivables
  extend ActiveSupport::Concern
  include Ageing

  OpenInvoice = Data.define(:sale, :amount_cents, :due_date, :outstanding_cents) do
    def days_overdue(as_of = Date.current) = (as_of - due_date).to_i
  end

  included do
    has_many :customer_payments, dependent: :restrict_with_error
  end

  class_methods do
    # Everyone who owes something, with what they owe. Customers with nothing ever put on
    # account are skipped without being loaded.
    def with_balances
      ids = Payment.on_account.joins(:sale).where(sales: { status: "completed" }).distinct.pluck("sales.customer_id")
      where(id: ids).alphabetically.map { [ _1, _1.balance_cents ] }.select { _2.nonzero? }
    end
  end

  # [sale, amount put on account] for each completed account sale, oldest first.
  def account_sales
    charges = Payment.on_account.joins(:sale).where(sales: { customer_id: id, status: "completed" }).group(:sale_id).sum(:amount_cents)
    sales.where(id: charges.keys).includes(:branch).order(:completed_at, :id).map { [ _1, charges[_1.id] ] }
  end

  def account_returns
    SaleReturn.joins(:sale).where(refund_method: "on_account", sales: { customer_id: id })
  end

  def charged_cents
    Payment.on_account.joins(:sale).where(sales: { customer_id: id, status: "completed" }).sum(:amount_cents)
  end

  def credited_cents
    account_returns.sum(:total_cents) + customer_payments.sum(:amount_cents)
  end

  def balance_cents
    charged_cents - credited_cents
  end

  def due_date_for(sale)
    sale.completed_at.to_date + payment_terms_days
  end

  def open_invoices
    unapplied = credited_cents

    account_sales.filter_map do |sale, amount|
      applied = [ unapplied, amount ].min
      unapplied -= applied
      OpenInvoice.new(sale, amount, due_date_for(sale), amount - applied) if applied < amount
    end
  end

  def statement(from: Date.current.beginning_of_month, to: Date.current)
    Customer::Statement.new(self, from: from, to: to)
  end
end
