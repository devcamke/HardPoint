# VAT for a return: tax charged on sales (less returns) by rate, tax paid on supplier invoices,
# and the difference owed to the tax authority.
class Report::Tax < Report
  self.title = "Tax (VAT)"
  self.description = "Output tax on sales by rate, input tax on supplier invoices, and VAT payable"
  self.group = "Sales and money"

  def sections
    [ Section.new(title: "Tax on sales (output tax)", columns: output_columns, rows: output_rows, totals: output_totals),
      Section.new(title: "Tax on purchases (input tax)", columns: input_columns, rows: [ input_row ],
        note: ("Supplier invoices aren't kept per branch, so this covers the whole shop." if branch)),
      Section.new(title: "Summary", columns: [ Column.new("", :text), Column.new("Amount", :money) ],
        rows: [ [ "Output tax", output_tax_cents ], [ "Input tax", -input_tax_cents ], [ "VAT payable", output_tax_cents - input_tax_cents ] ], emphasis: [ 2 ]) ]
  end

  def output_tax_cents = by_rate.values.sum { _1[:tax] }
  def input_tax_cents = input_invoices.sum(:tax_cents)

  private
    def output_columns
      [ Column.new("Rate", :text), Column.new("Sales incl. tax", :money), Column.new("Returns incl. tax", :money),
        Column.new("Net ex tax", :money), Column.new("Tax", :money) ]
    end

    def output_rows
      by_rate.sort.map { |rate, figures| output_row("#{rate.to_s("F").delete_suffix(".0")}%", figures) }
    end

    def output_totals
      output_row("Total", %i[ gross returns tax ].index_with { |field| by_rate.values.sum { _1[field] } })
    end

    def output_row(label, figures)
      [ label, figures[:gross], -figures[:returns], figures[:gross] - figures[:returns] - figures[:tax], figures[:tax] ]
    end

    def by_rate
      @by_rate ||= begin
        sold = sold_lines.group(:tax_rate)
          .pluck(:tax_rate, Arel.sql("ROUND(SUM(sale_lines.total_cents * #{PAID_SHARE}))"), Arel.sql("ROUND(SUM(sale_lines.tax_cents * #{PAID_SHARE}))"))
        returned = returned_lines.group("sale_lines.tax_rate")
          .pluck(Arel.sql("sale_lines.tax_rate"), Arel.sql("SUM(sale_return_lines.total_cents)"), Arel.sql("SUM(sale_return_lines.tax_cents)"))

        (sold.map(&:first) | returned.map(&:first)).index_with do |rate|
          _, gross, tax = sold.find { _1.first == rate } || [ rate, 0, 0 ]
          _, refunded, refunded_tax = returned.find { _1.first == rate } || [ rate, 0, 0 ]
          { gross: gross.to_i, returns: refunded.to_i, tax: tax.to_i - refunded_tax.to_i }
        end
      end
    end

    def input_columns
      [ Column.new("Invoices", :text), Column.new("Total incl. tax", :money), Column.new("Ex tax", :money), Column.new("Tax", :money) ]
    end

    def input_row
      total = input_invoices.sum(:total_cents)
      [ "#{input_invoices.count} supplier invoices dated in the period", total, total - input_tax_cents, input_tax_cents ]
    end

    def input_invoices
      account.supplier_invoices.where(invoice_date: period.dates)
    end
end
