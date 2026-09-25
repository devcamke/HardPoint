# How promotions did: completed sales that used them, units sold, what they took off, and takings.
class Promotion::Results
  Result = Data.define(:sales, :units, :saving_cents, :takings_cents)
  NONE = Result.new(sales: 0, units: 0, saving_cents: 0, takings_cents: 0)

  def self.for(promotions)
    ids = promotions.map(&:id)
    rows = SaleLine.joins(:sale).where(promotion_id: ids, sales: { status: "completed" }).group(:promotion_id)
      .pluck(:promotion_id, Arel.sql("COUNT(DISTINCT sale_lines.sale_id)"), Arel.sql("SUM(sale_lines.quantity)"),
        Arel.sql("SUM(sale_lines.promotion_discount_cents)"), Arel.sql("SUM(sale_lines.total_cents)"))
    found = rows.to_h { |id, sales, units, saving, takings| [ id, Result.new(sales: sales, units: units, saving_cents: saving.to_i, takings_cents: takings.to_i) ] }
    ids.index_with { found.fetch(_1, NONE) }
  end
end
