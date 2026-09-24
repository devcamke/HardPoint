# What stock is worth at cost, per branch, and a check that cached levels match the ledger.
class StockValuation
  Row = Data.define(:branch, :products_in_stock, :value_cents, :negative_lines)

  def initialize(account)
    @account = account
  end

  def rows
    totals = @account.stock_levels.joins(:product).group(:branch_id).pluck(
      :branch_id,
      Arel.sql("COUNT(*) FILTER (WHERE stock_levels.quantity > 0)"),
      Arel.sql("COALESCE(ROUND(SUM(GREATEST(stock_levels.quantity, 0) * products.cost_cents)), 0)"),
      Arel.sql("COUNT(*) FILTER (WHERE stock_levels.quantity < 0)")
    ).index_by(&:first)

    @account.branches.alphabetically.map do |branch|
      _, in_stock, value, negative = totals[branch.id] || [ nil, 0, 0, 0 ]
      Row.new(branch: branch, products_in_stock: in_stock, value_cents: value.to_i, negative_lines: negative)
    end
  end

  def total_value_cents
    rows.sum(&:value_cents)
  end

  # Levels whose quantity differs from the sum of their movements. Empty means the books balance.
  def mismatches
    @account.stock_levels
      .joins("LEFT JOIN (SELECT branch_id, product_id, SUM(quantity) AS total FROM stock_movements GROUP BY branch_id, product_id) ledger " \
             "ON ledger.branch_id = stock_levels.branch_id AND ledger.product_id = stock_levels.product_id")
      .where("stock_levels.quantity <> COALESCE(ledger.total, 0)")
  end

  def reconciled?
    mismatches.none?
  end
end
