# VAT for a return: tax charged on sales (less returns) by rate, tax paid on supplier invoices,
# and the difference owed to the tax authority.
class Report::Tax < Report
  self.title = "Tax (VAT)"
  self.description = "Output tax on sales by rate, input tax on supplier invoices, and VAT payable"
  self.group = "Sales and money"

  def sections
    [ Section.new(title: "Tax on sales (output tax)", columns: output_columns, rows: output_rows, totals: output_totals),
      Section.new(title: "Tax on purchases (input tax)", columns: input_columns, rows: input_rows,
        note: ("Supplier invoices aren't kept per branch, so this covers the whole shop." if branch)),
      Section.new(title: "Summary", columns: [ Column.new("", :text), Column.new("Amount", :money) ],
        rows: [ [ "Output tax", output_tax_cents ], [ "Input tax", -input_tax_cents ], [ "VAT payable", output_tax_cents - input_tax_cents ] ], emphasis: [ 2 ]) ]
  end

  def output_tax_cents = by_rate.values.sum { _1[:tax] }
  # Invoices in another currency count at the rate recorded on them; VAT on goods sent back to
  # suppliers (debit notes) in the period comes off.
  def input_tax_cents = invoiced_tax_cents - returned_tax_cents

  def invoiced_tax_cents = input_invoices.sum("ROUND(supplier_invoices.tax_cents * COALESCE(supplier_invoices.exchange_rate, 1))").to_i
  def returned_tax_cents = supplier_returns.sum("ROUND(supplier_returns.tax_cents * COALESCE(supplier_returns.exchange_rate, 1))").to_i

  private
    def output_columns
      [ Column.new("Rate", :text), Column.new("Sales incl. tax", :money), Column.new("Returns incl. tax", :money),
        Column.new("Net ex tax", :money), Column.new("Tax", :money) ]
    end

    # One row per tax rate of the shop's, so exempt and zero-rated sales, both 0%, are returned apart.
    def output_rows
      names = account.tax_rates.index_by(&:id)
      by_rate.sort_by { |(rate, id), _| [ rate, names[id]&.name.to_s ] }.map do |(rate, id), figures|
        percent = "#{rate.to_s("F").delete_suffix(".0")}%"
        output_row(names[id] ? "#{names[id].name} (#{percent})" : percent, figures)
      end
    end

    def output_totals
      output_row("Total", %i[ gross returns tax ].index_with { |field| by_rate.values.sum { _1[field] } })
    end

    def output_row(label, figures)
      [ label, figures[:gross], -figures[:returns], figures[:gross] - figures[:returns] - figures[:tax], figures[:tax] ]
    end

    # Keyed by [percentage, tax rate id]: the id tells two 0% rates apart; the percentage keeps lines sold
    # under a rate since edited, or with no rate at all, in the right row.
    def by_rate
      @by_rate ||= begin
        sold = sold_lines.group(:tax_rate, :tax_rate_id)
          .pluck(:tax_rate, :tax_rate_id, Arel.sql("ROUND(SUM(sale_lines.total_cents * #{PAID_SHARE}))"), Arel.sql("ROUND(SUM(sale_lines.tax_cents * #{PAID_SHARE}))"))
        returned = returned_lines.group("sale_lines.tax_rate", "sale_lines.tax_rate_id")
          .pluck(Arel.sql("sale_lines.tax_rate"), Arel.sql("sale_lines.tax_rate_id"), Arel.sql("SUM(sale_return_lines.total_cents)"), Arel.sql("SUM(sale_return_lines.tax_cents)"))

        (sold.map { _1.first(2) } | returned.map { _1.first(2) }).index_with do |key|
          *_, gross, tax = sold.find { _1.first(2) == key } || [ *key, 0, 0 ]
          *_, refunded, refunded_tax = returned.find { _1.first(2) == key } || [ *key, 0, 0 ]
          { gross: gross.to_i, returns: refunded.to_i, tax: tax.to_i - refunded_tax.to_i }
        end
      end
    end

    def input_columns
      [ Column.new("Invoices", :text), Column.new("Total incl. tax", :money), Column.new("Ex tax", :money), Column.new("Tax", :money) ]
    end

    def input_rows
      total = input_invoices.sum("ROUND(supplier_invoices.total_cents * COALESCE(supplier_invoices.exchange_rate, 1))").to_i
      rows = [ [ "#{input_invoices.count} supplier invoices dated in the period", total, total - invoiced_tax_cents, invoiced_tax_cents ] ]
      if supplier_returns.exists?
        returned = supplier_returns.sum("ROUND(supplier_returns.total_cents * COALESCE(supplier_returns.exchange_rate, 1))").to_i
        rows << [ "#{supplier_returns.count} #{"debit note".pluralize(supplier_returns.count)} for goods sent back", -returned, -(returned - returned_tax_cents), -returned_tax_cents ]
      end
      rows
    end

    def supplier_returns
      account.supplier_returns.where(created_at: period.range)
    end

    def input_invoices
      account.supplier_invoices.where(invoice_date: period.dates)
    end
end
