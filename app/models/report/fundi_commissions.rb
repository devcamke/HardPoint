# What each fundi brought in over the period, the commission it earned, what voids and returns took back, what was
# paid out, and what each is owed now.
class Report::FundiCommissions < Report
  self.title = "Fundi commissions"
  self.description = "Sales each fundi brought in, commission earned and paid, and what's owed"
  self.group = "Sales and money"
  self.feature = "fundis"

  def sections
    entries = account.fundi_entries.where(created_at: period.range)
    figures = entries.group(:fundi_id, :kind).pluck(:fundi_id, :kind, Arel.sql("SUM(amount_cents)"), Arel.sql("SUM(sales_cents)"))
      .each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |(id, kind, amount, sales), totals|
        totals[id][kind] += amount.to_i
        totals[id]["sales"] += sales.to_i unless kind == "paid"
      end
    owed = Fundi.balances_by_id

    rows = account.fundis.where(id: figures.keys | owed.select { _2.nonzero? }.keys).alphabetically.map do |fundi|
      totals = figures[fundi.id]
      [ Link.new(fundi.name, fundi), fundi.trade_name, totals["sales"], totals["earned"], -totals["reversed"], -totals["paid"], owed[fundi.id].to_i ]
    end.sort_by { -_1[2] }
    totals = [ "Total", nil, *(2..6).map { |index| rows.sum { _1[index] } } ]

    [ Section.new(columns: columns, rows: rows, totals: totals,
        note: "Sales are before tax, less any voided or returned. Owed is today's balance, whatever the period.") ]
  end

  private
    def columns
      [ Column.new("Fundi", :link), Column.new("Trade", :text), Column.new("Sales brought in", :money), Column.new("Earned", :money),
        Column.new("Taken back", :money), Column.new("Paid", :money), Column.new("Owed now", :money) ]
    end
end
