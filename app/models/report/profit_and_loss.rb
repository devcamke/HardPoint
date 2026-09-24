# A simple profit and loss: sales less returns (ex tax), less the cost of what was sold, less
# stock written off and cash paid out of the tills. Rent, wages and other overheads aren't in
# HardPoint, so this is the trading result, not the business's net profit.
class Report::ProfitAndLoss < Report
  self.title = "Profit and loss"
  self.description = "Sales, cost of sales, gross profit, stock losses and till payouts"
  self.group = "Sales and money"

  ADJUSTMENT_REASONS = %w[ found damaged stolen expired internal_use correction count ].freeze

  def sections
    rows = [
      [ "Sales ex tax", sales_cents ],
      [ "Returns ex tax", -returns_cents ],
      [ "Net sales", net_sales_cents ],
      [ "Cost of goods sold", -cost_of_sales_cents ],
      [ "Gross profit", gross_profit_cents ],
      [ "Gross margin", nil ],
      [ "Stock gains and losses (damaged, stolen, stock takes…)", stock_adjustments_cents ],
      [ "Paid out of the tills", -payouts_cents ],
      [ "Trading profit", trading_profit_cents ]
    ]
    rows[5][1] = percent(gross_profit_cents, net_sales_cents)&.round(1)&.then { "#{_1}%" }

    [ Section.new(columns: [ Column.new("", :text), Column.new("Amount", :money) ], rows: rows, emphasis: [ 2, 4, 8 ],
        note: "Purchases go into stock and only count here as they're sold. Rent, wages and other overheads aren't included."),
      Section.new(title: "Stock gains and losses by reason", columns: [ Column.new("Reason", :text), Column.new("Value at cost", :money) ],
        rows: adjustments_by_reason.map { |reason, cents| [ reason.humanize, cents ] }) ]
  end

  def sales_cents = @sales_cents ||= completed_sales.sum("sales.total_cents - sales.tax_cents").to_i
  def returns_cents = @returns_cents ||= returns.sum("sale_returns.total_cents - sale_returns.tax_cents").to_i
  def net_sales_cents = sales_cents - returns_cents

  def cost_of_sales_cents
    @cost_of_sales_cents ||= sold_lines.sum(:cost_cents) -
      returned_lines.where(restock: true)
        .sum("sale_lines.cost_cents * sale_return_lines.quantity / NULLIF(sale_lines.quantity, 0)").round
  end

  def gross_profit_cents = net_sales_cents - cost_of_sales_cents
  def stock_adjustments_cents = adjustments_by_reason.values.sum
  def trading_profit_cents = gross_profit_cents + stock_adjustments_cents - payouts_cents

  def payouts_cents
    @payouts_cents ||= begin
      scope = account.cash_movements.where(kind: "payout", created_at: period.range)
      scope = scope.joins(:shift).where(shifts: { branch_id: branch.id }) if branch
      scope.sum(:amount_cents)
    end
  end

  private
    def adjustments_by_reason
      @adjustments_by_reason ||= begin
        scope = account.stock_movements.where(reason: ADJUSTMENT_REASONS, created_at: period.range)
        scope = scope.where(branch: branch) if branch
        scope.group(:reason).sum("stock_movements.quantity * COALESCE(stock_movements.unit_cost_cents, 0)").transform_values(&:round).reject { _2.zero? }
      end
    end
end
