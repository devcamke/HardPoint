# What came in, by day and by method: sale takings (cash, M-Pesa, card, on account, deposits
# used), refunds, and money taken outside sales (deposits on orders, payments on account).
class Report::Payments < Report
  self.title = "Payments by method"
  self.description = "Takings by day and method, refunds, deposits and payments on account"
  self.group = "Sales and money"

  TENDER_LABELS = { "cash" => "Cash", "mobile_money" => "M-Pesa", "card" => "Card", "on_account" => "On account", "deposit" => "Deposits used", "foreign_cash" => "Foreign cash", "points" => "Points" }.freeze

  def sections
    [ Section.new(title: "Takings by day", columns: day_columns, rows: day_rows, totals: day_totals,
        note: "Sales put on account and deposits used aren't new money in; they're shown so the day adds up to its sales."),
      Section.new(title: "Money in outside sales", columns: [ Column.new("What", :text), Column.new("Method", :text), Column.new("Amount", :money) ],
        rows: other_money_rows, note: ("With a branch chosen, only payments on account taken at that branch's tills are shown." if branch)) ]
  end

  private
    # Foreign cash only has a column for shops that take it.
    def tender_labels
      @tender_labels ||= TENDER_LABELS.select do |tender, _|
        case tender
        when "foreign_cash" then account.currencies.exists? || takings.keys.any? { _2 == tender }
        when "points" then account.loyalty_program&.enabled? || takings.keys.any? { _2 == tender }
        else true
        end
      end
    end

    def day_columns
      [ Column.new("Day", :date), *tender_labels.values.map { Column.new(_1, :money) }, Column.new("Total", :money), Column.new("Refunds", :money) ]
    end

    def day_rows
      period.days <= Report::FILL_DAYS ? period.dates.map { day_row(_1) } : (takings.keys.map(&:first) | refunds.keys).sort.map { day_row(_1) }
    end

    def day_row(day)
      amounts = tender_labels.keys.map { takings.fetch([ day, _1 ], 0) }
      [ day, *amounts, amounts.sum, -refunds.fetch(day, 0) ]
    end

    def day_totals
      amounts = tender_labels.keys.map { |tender| takings.sum { |(_, key), cents| key == tender ? cents : 0 } }
      [ "Total", *amounts, amounts.sum, -refunds.values.sum ]
    end

    def takings
      @takings ||= Payment.where(sale_id: completed_sales.select(:id)).joins(:sale).group(Arel.sql(local_date("sales.completed_at")), :tender).sum(:amount_cents)
    end

    def refunds
      @refunds ||= returns.group(Arel.sql(local_date("sale_returns.created_at"))).sum(:total_cents)
    end

    def other_money_rows
      deposits = account.deposits.where(created_at: period.range)
      deposits = deposits.joins(:customer_order).where(customer_orders: { branch_id: branch.id }) if branch
      payments = account.customer_payments.where(paid_on: period.dates)
      payments = payments.joins(:shift).where(shifts: { branch_id: branch.id }) if branch

      deposits.where("amount_cents > 0").group(:tender).sum(:amount_cents).map { |tender, cents| [ "Deposits on orders", tender.humanize, cents ] } +
        deposits.where("amount_cents < 0").group(:tender).sum(:amount_cents).map { |tender, cents| [ "Deposits refunded", tender.humanize, cents ] } +
        payments.group(:payment_method).sum(:amount_cents).map { |method, cents| [ "Payments on account", method.humanize, cents ] }
    end
end
