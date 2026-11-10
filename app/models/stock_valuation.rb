# What stock is worth at cost, per branch and on the road between branches, and a check that cached
# levels match the ledger. Given branches, it covers only those: the stock at them, and transfers to or from them.
class StockValuation
  Row = Data.define(:branch, :products_in_stock, :value_cents, :negative_lines)
  InTransit = Data.define(:lines, :value_cents)

  def initialize(account, branches: nil)
    @account = account
    @branches = branches
  end

  def rows
    @rows ||= begin
      totals = stock_levels.joins(:product).group(:branch_id).pluck(
        :branch_id,
        Arel.sql("COUNT(*) FILTER (WHERE stock_levels.quantity > 0)"),
        Arel.sql("COALESCE(ROUND(SUM(GREATEST(stock_levels.quantity, 0) * products.cost_cents)), 0)"),
        Arel.sql("COUNT(*) FILTER (WHERE stock_levels.quantity < 0)")
      ).index_by(&:first)

      (@branches || @account.branches).alphabetically.map do |branch|
        _, in_stock, value, negative = totals[branch.id] || [ nil, 0, 0, 0 ]
        Row.new(branch: branch, products_in_stock: in_stock, value_cents: value.to_i, negative_lines: negative)
      end
    end
  end

  # Stock one branch has sent and the other hasn't received: out of the sender's books, not yet in the
  # receiver's, so it's valued on its own rather than vanishing from the total.
  def in_transit
    @in_transit ||= begin
      lines, value = transfers.in_transit.joins(lines: :product)
        .pick(Arel.sql("COUNT(stock_transfer_lines.id)"), Arel.sql("COALESCE(ROUND(SUM(stock_transfer_lines.quantity * products.cost_cents)), 0)"))
      InTransit.new(lines: lines.to_i, value_cents: value.to_i)
    end
  end

  def total_value_cents
    rows.sum(&:value_cents) + in_transit.value_cents
  end

  # Levels whose quantity differs from the sum of their movements. Empty means the books balance.
  def mismatches
    stock_levels
      .joins("LEFT JOIN (SELECT branch_id, product_id, SUM(quantity) AS total FROM stock_movements GROUP BY branch_id, product_id) ledger " \
             "ON ledger.branch_id = stock_levels.branch_id AND ledger.product_id = stock_levels.product_id")
      .where("stock_levels.quantity <> COALESCE(ledger.total, 0)")
  end

  # Adding up the whole ledger grows with every sale, so the Stock page shows a check at most RECONCILE_EVERY old.
  RECONCILE_EVERY = 15.minutes

  def reconciled?
    Rails.cache.fetch([ "stock-reconciled", @account.id, *@branches&.ids&.sort ], expires_in: RECONCILE_EVERY) { mismatches.none? }
  end

  private
    def stock_levels
      @branches ? @account.stock_levels.where(branch_id: @branches.select(:id)) : @account.stock_levels
    end

    def transfers
      transfers = @account.stock_transfers
      @branches ? transfers.where(from_branch_id: @branches.select(:id)).or(transfers.where(to_branch_id: @branches.select(:id))) : transfers
    end
end
