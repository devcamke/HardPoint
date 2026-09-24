# The owner's view of today: takings and margin against the same day last week, sales by hour
# and branch, best sellers, cash in the drawers, money owed both ways, and what needs doing.
# Built from the same queries as the reports, so the numbers always agree.
class Dashboard
  attr_reader :account, :branch, :date

  def initialize(account, branch: nil, date: Time.zone.today)
    @account = account
    @branch = branch
    @date = date
  end

  def today
    @today ||= sales_report(date, by: "product")
  end

  def same_day_last_week
    @same_day_last_week ||= sales_report(date - 7, by: "branch")
  end

  # [ takings, receipts, net ex tax, gross margin, margin % ] for the day.
  def totals(report = today)
    _, receipts, *rest = report.sections.first.totals
    takings, _returns, _tax, net, _cost, margin, margin_percent = rest.last(7)
    { receipts: receipts, takings: takings, net: net, margin: margin, margin_percent: margin_percent }
  end

  def change_on_last_week_percent
    before = totals(same_day_last_week)[:takings]
    before.zero? ? nil : ((totals[:takings] - before) * 100.0 / before).round
  end

  def average_sale_cents
    receipts = totals[:receipts]
    receipts.zero? ? 0 : totals[:takings] / receipts
  end

  def top_products(limit = 5)
    today.sections.first.rows.first(limit).map { |row| { product: row[0], quantity: row[2], takings: row[3] } }
  end

  # Takings per hour of the day, in the shop's time zone, from opening to the last sale.
  def takings_by_hour
    sales = account.sales.completed.where(completed_at: date.all_day)
    sales = sales.where(branch: branch) if branch
    hours = sales.group(Arel.sql("EXTRACT(HOUR FROM ((sales.completed_at AT TIME ZONE 'UTC') AT TIME ZONE #{ActiveRecord::Base.connection.quote(time_zone)}))::int"))
      .sum(:total_cents)
    return {} if hours.empty?

    ([ hours.keys.min, 7 ].min..[ hours.keys.max, 18 ].max).index_with { hours.fetch(_1, 0) }
  end

  def last_seven_days
    @last_seven_days ||= Report::Sales.new(account: account, period: Report::Period.new(from: date - 6, to: date), branch: branch, options: { by: "day" })
      .sections.first.rows.map { |day, _receipts, takings, *| [ day, takings ] }
  end

  def takings_by_branch
    return [] if branch

    sales_report(date, by: "branch").sections.first.rows.map { |name, _receipts, takings, *| [ name, takings ] }
  end

  # What should be in each open till right now.
  def cash_in_drawers
    shifts = account.shifts.open.includes(:register, :opened_by)
    shifts = shifts.where(branch: branch) if branch
    shifts.map { { shift: _1, expected_cents: _1.expected_cash_cents_now } }
  end

  def owed_to_us
    rows = account.customers.with_balances
    { total: rows.sum(&:last), overdue: rows.sum { |customer, _| customer.overdue_cents }, customers: rows.size }
  end

  def owed_by_us
    suppliers = account.suppliers.to_a.select { _1.balance_cents.positive? }
    { total: suppliers.sum(&:balance_cents), overdue: suppliers.sum(&:overdue_cents), suppliers: suppliers.size }
  end

  # Products to reorder, counted once per branch that's low on them.
  def low_stock_count
    (branch ? [ branch ] : account.branches).sum { account.products.active.below_reorder_level_at(_1).count }
  end

  def orders_ready_count
    orders = account.customer_orders.ready
    branch ? orders.where(branch: branch).count : orders.count
  end

  def deliveries_outstanding_count
    notes = account.delivery_notes.outstanding
    branch ? notes.where(branch: branch).count : notes.count
  end

  private
    def sales_report(day, by:)
      Report::Sales.new(account: account, period: Report::Period.new(from: day, to: day), branch: branch, options: { by: by })
    end

    def time_zone
      ActiveSupport::TimeZone[account.time_zone].tzinfo.identifier
    end
end
