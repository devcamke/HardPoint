# The owner's Monday email for the week just ended (Monday to Sunday): takings against the weeks before, the best
# sellers and their margin, who owes the shop and how late, what the shop owes this week, and stock that isn't selling.
class OwnerSummary::Weekly
  WEEKS = 8
  DEAD_STOCK_DAYS = 90
  LIST_LIMIT = 8

  Week = Data.define(:starts_on, :takings_cents)
  Seller = Data.define(:name, :quantity, :takings_cents, :margin_cents)
  Debtor = Data.define(:customer, :overdue_cents, :balance_cents)
  Bill = Data.define(:supplier, :invoice, :due_on, :outstanding_cents)

  attr_reader :account, :ends_on

  def initialize(account, ends_on)
    @account = account
    @ends_on = ends_on
  end

  def starts_on = ends_on - 6
  def currency = account.currency
  def totals = @totals ||= totals_for(starts_on..ends_on)
  def last_week_totals = @last_week_totals ||= totals_for((starts_on - 7)..(ends_on - 7))

  def change_on_last_week_percent
    before = last_week_totals[:takings]
    before.zero? ? nil : ((totals[:takings] - before) * 100.0 / before).round
  end

  # Takings for each of the last eight weeks, this one last.
  def weeks
    @weeks ||= begin
      daily = Report::Sales.new(account: account, period: Report::Period.new(from: starts_on - 7 * (WEEKS - 1), to: ends_on), options: { by: "day" })
        .sections.first.rows.to_h { |day, _receipts, takings, *| [ day.to_date, takings ] }
      (0...WEEKS).map do |index|
        week_start = starts_on - 7 * (WEEKS - 1 - index)
        Week.new(week_start, (week_start..week_start + 6).sum { daily.fetch(_1, 0) })
      end
    end
  end

  # Takings on each day of the week.
  def days
    @days ||= Report::Sales.new(account: account, period: period, options: { by: "day" }).sections.first.rows.map { |day, _receipts, takings, *| [ day.to_date, takings ] }
  end

  def best_sellers
    @best_sellers ||= Report::Sales.new(account: account, period: period, options: { by: "product" }).sections.first.rows.first(LIST_LIMIT).map do |row|
      takings, _returns, _tax, _net, _cost, margin = row.last(7)
      Seller.new(row[0].respond_to?(:record) ? row[0].record.name : row[0].to_s, row[2], takings, margin)
    end
  end

  # What customers owe, by how late it is, and the ones most overdue.
  def receivables
    @receivables ||= begin
      rows = account.customers.with_balances(account: account).select { _2.positive? }
      ageing = Customer.ageing_by_id(rows.map(&:first), account: account)
      buckets = Ageing::BUCKETS.keys.index_with { |bucket| rows.sum { ageing.dig(_1.first.id, bucket).to_i } }
      debtors = rows.map { |customer, balance| Debtor.new(customer, Ageing.overdue_in(ageing[customer.id] || {}), balance) }
        .select { _1.overdue_cents.positive? }.sort_by { -_1.overdue_cents }
      { total: rows.sum(&:last), buckets: buckets, debtors: debtors.first(5), overdue_customers: debtors.size }
    end
  end

  # Supplier bills due in the coming week, and what's already overdue.
  def payables
    @payables ||= begin
      bills = account.suppliers.includes(:supplier_invoices).flat_map do |supplier|
        supplier.open_invoices.map { Bill.new(supplier, _1.invoice, _1.invoice.due_date, _1.outstanding_cents) }
      end
      today = ends_on + 1
      { due: bills.select { _1.due_on.between?(today, today + 6) }.sort_by(&:due_on),
        overdue_cents: bills.select { _1.due_on < today }.sum(&:outstanding_cents) }
    end
  end

  # Stock that hasn't sold in 90 days, the most money tied up first.
  def dead_stock
    @dead_stock ||= begin
      section = Report::DeadStock.new(account: account, period: period, options: { days: DEAD_STOCK_DAYS.to_s }).sections.first
      { value_cents: section.totals[4].to_i, count: section.rows.size,
        products: section.rows.first(5).map { |link, _category, on_hand, unit, value, *| [ link.record.name, on_hand, unit, value ] } }
    end
  end

  private
    def period = Report::Period.new(from: starts_on, to: ends_on)

    def totals_for(dates)
      _, receipts, *rest = Report::Sales.new(account: account, period: Report::Period.new(from: dates.first, to: dates.last), options: { by: "branch" }).sections.first.totals
      takings, _returns, _tax, net, _cost, margin, margin_percent = rest.last(7)
      { receipts: receipts, takings: takings, net: net, margin: margin, margin_percent: margin_percent }
    end
end
