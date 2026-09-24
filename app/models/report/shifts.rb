# Every shift closed in the period with its sales and how the cash count came out.
class Report::Shifts < Report
  self.title = "Shifts and cash counts"
  self.description = "Closed shifts with their sales, expected and counted cash, and over/short"
  self.group = "Sales and money"

  def sections
    shifts = account.shifts.closed.where(closed_at: period.range).includes(:register, :opened_by, :closed_by).order(:closed_at)
    shifts = shifts.where(branch: branch) if branch
    takings = account.sales.completed.where(shift: shifts).group(:shift_id).sum(:total_cents)

    rows = shifts.map do |shift|
      [ Link.new(shift.name, shift), shift.opened_by.name, I18n.l(shift.opened_at, format: :short), I18n.l(shift.closed_at, format: :short),
        takings.fetch(shift.id, 0), shift.expected_cash_cents, shift.counted_cash_cents, shift.variance_cents ]
    end
    totals = [ "Total", nil, nil, nil, *(4..7).map { |index| rows.sum { _1[index].to_i } } ]

    [ Section.new(columns: columns, rows: rows, totals: totals, note: "Over/short is counted cash less expected cash; negative means the drawer was short.") ]
  end

  private
    def columns
      [ Column.new("Shift", :link), Column.new("Opened by", :text), Column.new("Opened", :text), Column.new("Closed", :text),
        Column.new("Sales", :money), Column.new("Expected cash", :money), Column.new("Counted", :money), Column.new("Over/short", :money) ]
    end
end
