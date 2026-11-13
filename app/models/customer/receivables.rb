# What a customer owes on account. A sale put (partly) on account is the invoice, due after the
# customer's payment terms; so is an opening balance, what they owed when the shop moved to HardPoint,
# which has no sale behind it. Payments, write-offs and returns credited to the account settle the oldest
# invoices first (FIFO), except where a payment was put against particular sales (its allocations),
# which settle those sales and only those; the ageing report and statements are based on this.
# The balance itself is always the whole ledger: charges less credits.
module Customer::Receivables
  extend ActiveSupport::Concern
  include Ageing

  OpenInvoice = Data.define(:sale, :amount_cents, :due_date, :outstanding_cents) do
    def days_overdue(as_of = Date.current) = (as_of - due_date).to_i
    # An opening balance has no sale.
    def opening_balance? = sale.nil?
    def reference = sale ? sale.receipt_number : "Opening balance"
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
    # settling as #open_invoices.
    def ageing_by_id(customers, as_of: Date.current, account: Current.account)
      customers = customers.to_a
      ids = customers.map(&:id)
      credited = credited_by_id(ids, account)
      allocated = CustomerPaymentAllocation.joins(:customer_payment).where(customer_payments: { account_id: account.id, customer_id: ids })
        .group("customer_payments.customer_id", :sale_id).sum(:amount_cents)
      allocated_by_customer = allocated.each_with_object(Hash.new(0)) { |((customer_id, _), cents), totals| totals[customer_id] += cents }
      charges = Payment.on_account.joins(:sale).where(sales: { account_id: account.id, customer_id: ids, status: "completed" })
        .group("sales.customer_id", "sales.id", "sales.completed_at").order("sales.completed_at", "sales.id").sum(:amount_cents)
        .group_by { |(customer_id, *), _| customer_id }
      # Opening balances are charges too: [ date, sale id (none), amount ], ahead of that day's sales.
      openings = account.customer_payments.opening_balances.where(customer_id: ids, amount_cents: ...0).pluck(:customer_id, :paid_on, :amount_cents)
        .group_by(&:first).transform_values { |rows| rows.map { |_, paid_on, cents| [ paid_on, nil, cents.abs ] } }

      customers.to_h do |customer|
        opening = openings[customer.id] || []
        sold = (charges[customer.id] || []).map { |(_, sale_id, completed_at), amount| [ completed_at.in_time_zone.to_date, sale_id, amount ] }
        # The credits were summed with the opening balance in them as a negative; put it back.
        unapplied = [ credited[customer.id].to_i + opening.sum(&:last) - allocated_by_customer[customer.id], 0 ].max
        open = (opening + sold).sort_by.with_index { |(date, sale_id, _), index| [ date, sale_id ? 1 : 0, index ] }.filter_map do |date, sale_id, amount|
          outstanding = amount - (sale_id ? allocated.fetch([ customer.id, sale_id ], 0) : 0)
          applied = [ unapplied, outstanding ].min
          unapplied -= applied
          OpenInvoice.new(nil, amount, date + customer.payment_terms_days, outstanding - applied) if applied < outstanding
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

  # [sale, amount put on account] for each completed account sale, oldest first; up to the end of as_of when given.
  def account_sales(as_of: nil)
    charges = Payment.on_account.joins(:sale).where(sales: { customer_id: id, status: "completed" }).group(:sale_id).sum(:amount_cents)
    completed = sales.where(id: charges.keys)
    completed = completed.where(completed_at: ..end_of(as_of)) if as_of
    completed.includes(:branch).order(:completed_at, :id).map { [ _1, charges[_1.id] ] }
  end

  def account_returns(as_of: nil)
    returns = SaleReturn.joins(:sale).where(refund_method: "on_account", sales: { customer_id: id })
    as_of ? returns.where(created_at: ..end_of(as_of)) : returns
  end

  def charged_cents
    Payment.on_account.joins(:sale).where(sales: { customer_id: id, status: "completed" }).sum(:amount_cents)
  end

  def credited_cents(as_of: nil)
    payments = as_of ? customer_payments.where(paid_on: ..as_of) : customer_payments
    account_returns(as_of: as_of).sum(:total_cents) + payments.sum(:amount_cents)
  end

  # What the customer owed when the shop moved to HardPoint, if that was brought across: the entry, or nil.
  # (Credit brought across isn't a debt; it settles invoices like any payment.)
  def opening_debt(as_of: nil)
    entries = customer_payments.opening_balances.where(amount_cents: ...0)
    (as_of ? entries.where(paid_on: ..as_of) : entries).first
  end

  def balance_cents
    @balance_cents || (charged_cents - credited_cents)
  end

  # Works the balance out once, for a page that shows it in several places.
  def remember_balance
    tap { self.balance_cents = balance_cents }
  end

  def due_date_for(sale)
    sale.completed_at.to_date + payment_terms_days
  end

  # What's still owed on each account sale and on the opening balance, as of a day (today unless told
  # otherwise). Credits put against particular sales come off those; everything else comes off the oldest first.
  def open_invoices(as_of: nil)
    allocated = CustomerPaymentAllocation.joins(:customer_payment).where(customer_payments: { customer_id: id })
    allocated = allocated.where(customer_payments: { paid_on: ..as_of }) if as_of
    allocated = allocated.group(:sale_id).sum(:amount_cents)
    opening = opening_debt(as_of: as_of)
    # The credits were summed with the opening balance in them as a negative; put it back.
    unapplied = [ credited_cents(as_of: as_of) + opening&.amount_cents.to_i.abs - allocated.values.sum, 0 ].max

    charges = account_sales(as_of: as_of).map { |sale, amount| [ due_date_for(sale) - payment_terms_days, sale, amount ] }
    charges.unshift [ opening.paid_on, nil, opening.amount_cents.abs ] if opening
    charges.sort_by.with_index { |(date, sale, _), index| [ date, sale ? 1 : 0, index ] }.filter_map do |date, sale, amount|
      outstanding = amount - (sale ? allocated.fetch(sale.id, 0) : 0)
      applied = [ unapplied, outstanding ].min
      unapplied -= applied
      OpenInvoice.new(sale, amount, date + payment_terms_days, outstanding - applied) if applied < outstanding
    end
  end

  # The ageing as of a day only settles what had happened by then, so a backdated statement's buckets add
  # up to its closing balance.
  def ageing(as_of: Date.current)
    Ageing.buckets_for(open_invoices(as_of: as_of), as_of: as_of)
  end

  # Given the open invoices already worked out, from those.
  def overdue_cents(as_of: Date.current, invoices: open_invoices(as_of: as_of))
    invoices.select { _1.days_overdue(as_of).positive? }.sum(&:outstanding_cents)
  end

  def statement(from: Date.current.beginning_of_month, to: Date.current)
    Customer::Statement.new(self, from: from, to: to)
  end

  private
    # The last moment of a day in the shop's time zone.
    def end_of(date)
      date.in_time_zone(account.time_zone).end_of_day
    end
end
