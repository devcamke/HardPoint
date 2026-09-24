# Takings, returns, tax, cost and gross margin, grouped by day, branch, cashier, category or
# product. Cart discounts are spread over their lines, so every grouping adds up to the same
# totals. Margin is on sales ex tax against what the goods cost when they were sold.
class Report::Sales < Report
  self.title = "Sales and margin"
  self.description = "Takings, returns, tax, cost and gross margin by day, branch, cashier, category or product"
  self.group = "Sales and money"

  GROUPINGS = { "day" => "Day", "month" => "Month", "branch" => "Branch", "cashier" => "Cashier", "category" => "Category", "product" => "Product" }.freeze

  def self.options
    [ [ :by, "Group by", GROUPINGS.invert.to_a, "day" ] ]
  end

  def sections
    [ Section.new(columns: columns, rows: rows, totals: totals, note: note) ]
  end

  def by
    options[:by].presence_in(GROUPINGS.keys) || "day"
  end

  private
    Figures = Struct.new(:receipts, :quantity, :takings, :returns, :tax, :cost, keyword_init: true) do
      def net = takings - returns - tax
      def margin = net - cost
    end

    def columns
      [ Column.new(GROUPINGS[by], by == "day" ? :date : (by == "product" ? :link : :text)),
        Column.new("Receipts", :count),
        (Column.new("Quantity", :quantity) if by == "product"),
        Column.new("Takings", :money), Column.new("Returns", :money), Column.new("Tax", :money),
        Column.new("Net sales ex tax", :money), Column.new("Cost", :money), Column.new("Gross margin", :money),
        Column.new("Margin %", :percent) ].compact
    end

    def rows
      @rows ||= begin
        keys = figures.keys
        keys = (period.dates.to_a | keys) if by == "day" && period.days <= Report::FILL_DAYS
        keys = by.in?(%w[ day month ]) ? keys.sort : keys.sort_by { -figures[_1].net }
        keys.map { |key| row(label_for(key), figures[key] || Figures.new(receipts: 0, quantity: 0, takings: 0, returns: 0, tax: 0, cost: 0)) }
      end
    end

    def totals
      all = figures.values
      sum = Figures.new(**%i[ receipts quantity takings returns tax cost ].index_with { |field| all.sum(&field) })
      row("Total", sum)
    end

    def row(label, figures)
      [ label, figures.receipts, (figures.quantity if by == "product"), figures.takings, -figures.returns, figures.tax,
        figures.net, figures.cost, figures.margin, percent(figures.margin, figures.net) ].then { |cells| by == "product" ? cells : cells.values_at(0, 1, 3..9) }
    end

    def note
      against = by.in?(%w[ day month ]) ? "" : ", against the original sale's #{GROUPINGS[by].downcase}"
      "Returns count when they happen#{against}. Returned goods put back on the shelf take their cost back out; written-off returns don't."
    end

    def figures
      @figures ||= begin
        sold = sold_lines.group(group_expression("sales.completed_at")).pluck(
          group_expression("sales.completed_at"),
          Arel.sql("COUNT(DISTINCT sales.id)"),
          Arel.sql("SUM(sale_lines.quantity * COALESCE(product_units.quantity, 1))"),
          Arel.sql("ROUND(SUM(sale_lines.total_cents * #{PAID_SHARE}))"),
          Arel.sql("ROUND(SUM(sale_lines.tax_cents * #{PAID_SHARE}))"),
          Arel.sql("SUM(sale_lines.cost_cents)"))
        returned = returned_lines.group(group_expression("sale_returns.created_at")).pluck(
          group_expression("sale_returns.created_at"),
          Arel.sql("SUM(sale_return_lines.quantity * COALESCE(product_units.quantity, 1))"),
          Arel.sql("SUM(sale_return_lines.total_cents)"),
          Arel.sql("SUM(sale_return_lines.tax_cents)"),
          Arel.sql("ROUND(SUM(CASE WHEN sale_return_lines.restock THEN sale_lines.cost_cents * sale_return_lines.quantity / NULLIF(sale_lines.quantity, 0) ELSE 0 END))")
        ).index_by(&:first)

        (sold.map(&:first) | returned.keys).index_with do |key|
          _, receipts, quantity, takings, tax, cost = sold.find { _1.first == key } || [ key, 0, 0, 0, 0, 0 ]
          _, returned_quantity, refunded, refunded_tax, restocked_cost = returned[key] || [ key, 0, 0, 0, 0 ]
          Figures.new(receipts: receipts.to_i, quantity: quantity.to_d - returned_quantity.to_d, takings: takings.to_i, returns: refunded.to_i,
            tax: tax.to_i - refunded_tax.to_i, cost: cost.to_i - restocked_cost.to_i)
        end
      end
    end

    def sold_lines
      super.joins(:product).left_joins(:product_unit)
    end

    def returned_lines
      super.joins(sale_line: :product).left_joins(sale_line: :product_unit)
    end

    def group_expression(date_column)
      Arel.sql case by
      when "day" then local_date(date_column)
      when "month" then "date_trunc('month', #{local_date(date_column)})::date"
      when "branch" then "sales.branch_id"
      when "cashier" then "sales.cashier_id"
      when "category" then "products.category_id"
      when "product" then "sale_lines.product_id"
      end
    end

    def label_for(key)
      @labels ||= case by
      when "branch" then account.branches.where(id: figures.keys).to_h { [ _1.id, _1.name ] }
      when "cashier" then account.users.where(id: figures.keys).to_h { [ _1.id, _1.name ] }
      when "category" then account.categories.where(id: figures.keys).to_h { [ _1.id, _1.name ] }
      when "product" then account.products.where(id: figures.keys).to_h { [ _1.id, Link.new("#{_1.name} (#{_1.sku})", _1) ] }
      else {}
      end
      return key if by == "day"
      return key.strftime("%B %Y") if by == "month"

      @labels.fetch(key) { key.nil? ? "Uncategorised" : "Unknown" }
    end
end
