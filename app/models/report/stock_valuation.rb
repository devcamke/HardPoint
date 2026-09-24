# What stock on hand is worth right now, at cost and at selling price, by category, with the
# margin it would make if sold at full price.
class Report::StockValuation < Report
  self.title = "Stock valuation"
  self.description = "Stock on hand at cost and at selling price, by category and branch"
  self.group = "Stock"
  self.uses_period = false

  def sections
    [ Section.new(title: "By category", columns: columns("Category"), rows: category_rows, totals: row("Total", category_figures.values.transpose.map(&:sum).presence || [ 0, 0, 0, 0 ]),
        note: "Only stock above zero is valued. Selling value is at full retail price including tax; margin is ex tax."),
      (Section.new(title: "By branch", columns: columns("Branch"), rows: branch_rows) unless branch) ].compact
  end

  private
    def columns(label)
      [ Column.new(label, :text), Column.new("Products in stock", :count), Column.new("Value at cost", :money), Column.new("Selling value", :money),
        Column.new("Potential margin", :money), Column.new("Margin %", :percent) ]
    end

    def row(label, (products, cost, retail, retail_ex_tax))
      [ label, products, cost, retail, retail_ex_tax - cost, percent(retail_ex_tax - cost, retail_ex_tax) ]
    end

    def levels
      scope = account.stock_levels.joins(:product).where("stock_levels.quantity > 0")
        .joins("LEFT JOIN tax_rates ON tax_rates.id = COALESCE(products.tax_rate_id, #{default_tax_rate&.id.to_i})")
      branch ? scope.where(branch: branch) : scope
    end

    def figures_by(column)
      levels.group(column).pluck(column,
        Arel.sql("COUNT(DISTINCT products.id)"),
        Arel.sql("ROUND(SUM(stock_levels.quantity * products.cost_cents))"),
        Arel.sql("ROUND(SUM(stock_levels.quantity * products.price_cents))"),
        Arel.sql("ROUND(SUM(stock_levels.quantity * products.price_cents * 100 / (100 + COALESCE(tax_rates.rate, 0))))"))
        .to_h { |key, *figures| [ key, figures.map(&:to_i) ] }
    end

    def category_figures
      @category_figures ||= figures_by(Arel.sql("products.category_id"))
    end

    def category_rows
      names = account.categories.where(id: category_figures.keys).to_h { [ _1.id, _1.name ] }
      category_figures.sort_by { -_2[1] }.map { |id, figures| row(names.fetch(id, "Uncategorised"), figures) }
    end

    def branch_rows
      names = account.branches.to_h { [ _1.id, _1.name ] }
      figures_by(Arel.sql("stock_levels.branch_id")).sort_by { -_2[1] }.map { |id, figures| row(names[id], figures) }
    end

    def default_tax_rate
      account.tax_rates.find_by(default: true)
    end
end
