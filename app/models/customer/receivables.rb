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
    # Everyone who owes something, with what they owe, worked out in three grouped queries for the whole shop
    # rather than three per customer. Customers with nothing owed are skipped without being loaded.
    def with_balances(account: Current.account)
      balances = balances_by_id(account: account).select { _2.nonzero? }
      where(id: balances.keys).alphabetically.map { |customer| [ customer.tap { _1.balance_cents = balances[_1.id] }, balances[customer.id] ] }
    end

    # { customer id => balance } for every customer who has had anything on account (or the ids given).
    def balances_by_id(ids = nil, account: Current.account)
      charged = charged_by_id(ids, account)
      credited = credited_by_id(ids, account)
      (charged.keys | credited.keys).index_with { charged[_1].to_i - credited[_1].to_i }
    end

    # { customer id => ageing buckets } for these customers, from one query for their account sales; the same
    # oldest-first settling as #open_invoices.
    def ageing_by_id(customers, as_of: Date.current, account: Current.account)
      customers = customers.to_a
      credited = credited_by_id(customers.map(&:id), account)
      charges = Payment.on_account.joins(:sale).where(sales: { account_id: account.id, customer_id: customers.map(&:id), status: "completed" })
        .group("sales.customer_id", "sales.id", "sales.completed_at").order("sales.completed_at", "sales.id").sum(:amount_cents)
        .group_by { |(customer_id, *), _| customer_id }

      customers.to_h do |customer|
        unapplied = credited[customer.id].to_i
        open = (charges[customer.id] || []).filter_map do |(_, _, completed_at), amount|
          applied = [ unapplied, amount ].min
          unapplied -= applied
          OpenInvoice.new(nil, amount, completed_at.in_time_zone.to_date + customer.payment_terms_days, amount - applied) if applied < amount
        end
        [ customer.id, Ageing.buckets_for(open, as_of: as_of) ]
      end
    end

    private
      def charged_by_id(ids, account)
        scope = Payment.on_account.joins(:sale).where(sales: { account_id: account.id, status: "completed" })
        scope = scope.where(sales: { customer_id: ids }) if ids
        scope.group("sales.customer_id").sum(:amount_cents)
      end

      def credited_by_id(ids, account)
        returns = SaleReturn.joins(:sale).where(refund_method: "on_account", sales: { account_id: account.id })
        returns = returns.where(sales: { customer_id: ids }) if ids
        payments = account.customer_payments
        payments = payments.where(customer_id: ids) if ids
        returns.group("sales.customer_id").sum(:total_cents).merge(payments.group(:customer_id).sum(:amount_cents)) { |_, a, b| a + b }
      end
  end

  # Set when the balance was worked out for many customers at once (lists, the API), so it isn't asked again.
  attr_writer :balance_cents

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
    @balance_cents || (charged_cents - credited_cents)
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
