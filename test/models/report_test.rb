require "test_helper"

class ReportTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @zone, Time.zone = Time.zone, accounts(:acme).time_zone
    @shift = shifts(:acme_front_open)
    @today = Report::Period.for_preset("today")
  end

  teardown { Time.zone = @zone }

  def sell(product, quantity: 1, tender: "cash", discount_cents: 0)
    sale = @shift.current_sale
    sale.add(product, quantity: quantity)
    if discount_cents.positive?
      sale.update!(discount_cents: discount_cents)
      sale.recalculate
    end
    sale.pay(tender: tender, reference: "QWE123")
    sale.reload
  end

  def report(key, period: @today, **options)
    Report.find(key).new(account: Current.account, period: period, options: options)
  end

  test "a sale line keeps what it cost when it was sold" do
    sale = sell(products(:acme_nails), quantity: 4)
    products(:acme_nails).update!(cost_cents: 99_999)

    assert_equal 4 * 18000, sale.lines.sole.cost_cents
  end

  test "sales and margin add up the same whichever way they're grouped" do
    sell(products(:acme_nails), quantity: 4, discount_cents: 10000) # 1,000.00 less 100.00
    sell(products(:acme_pipe), tender: "mobile_money")

    totals = %w[ day month branch cashier category product ].map { report("sales", by: _1).sections.first.totals.last(7) }
    assert_equal 1, totals.uniq.size

    takings, returns, tax, net, cost, margin, _percent = totals.first
    assert_equal 90000 + 120000, takings
    assert_equal 0, returns
    assert_equal (90000 * 16 / 116.0).round + (120000 * 16 / 116.0).round, tax
    assert_equal 72000 + 90000, cost
    assert_equal takings - tax - cost, margin
    assert_equal takings - tax, net
  end

  test "restocked returns take their cost back out of cost of sales" do
    sale = sell(products(:acme_nails), quantity: 4)
    Current.account.sale_returns.create!(sale: sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.first, quantity: 1, restock: true } ])

    by_product = report("sales", by: "product").sections.first
    product_row = by_product.rows.sole
    assert_equal 3, product_row[2], "net quantity sold"
    assert_equal(-25000, product_row[4], "returns")
    assert_equal 3 * 18000, product_row[7], "cost of what was kept"

    pnl = report("profit_and_loss")
    assert_equal 3 * 18000, pnl.cost_of_sales_cents
    assert_equal 100000 - (100000 * 16 / 116.0).round - (25000 - (25000 * 16 / 116.0).round), pnl.net_sales_cents
  end

  test "profit and loss takes off stock losses and till payouts" do
    sell(products(:acme_nails), quantity: 4)
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -2, reason: "damaged")
    @shift.cash_movements.create!(account: Current.account, kind: "payout", amount_cents: 5000, reason: "Tea")

    pnl = report("profit_and_loss")
    assert_equal(-2 * 70000, pnl.stock_adjustments_cents)
    assert_equal 5000, pnl.payouts_cents
    assert_equal pnl.gross_profit_cents - 140000 - 5000, pnl.trading_profit_cents
  end

  test "VAT payable is output tax less input tax" do
    sell(products(:acme_nails), quantity: 4)
    Current.account.supplier_invoices.create!(supplier: suppliers(:acme_cement_distributor), number: "INV-1", invoice_date: Date.current,
      total_cents: 116000, tax_cents: 16000)

    tax = report("tax")
    assert_equal (100000 * 16 / 116.0).round, tax.output_tax_cents
    assert_equal 16000, tax.input_tax_cents
    assert_equal [ "VAT payable", tax.output_tax_cents - 16000 ], tax.sections.last.rows.last
  end

  test "payments by method and refunds by day" do
    sell(products(:acme_nails), quantity: 4)
    sale = sell(products(:acme_pipe), tender: "card")
    Current.account.sale_returns.create!(sale: sale, shift: @shift, refund_method: "card", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.first, quantity: 1, restock: true } ])

    today = report("payments").sections.first.rows.sole
    assert_equal [ Date.current, 100000, 0, 120000, 0, 0, 220000, -120000 ], today
  end

  test "discounts and voids per cashier, with every voided sale" do
    sell(products(:acme_nails), quantity: 4, discount_cents: 2000)
    voided = sell(products(:acme_pipe))
    voided.void(reason: "Rang up twice", by: users(:amina))

    by_cashier, voids, discounts = report("discounts_and_voids").sections
    assert_equal [ "Carl Cashier", 1, 2000, 1, 1, 120000, 0, 0 ], by_cashier.rows.sole
    assert_equal voided.receipt_number, voids.rows.sole.first.text
    assert_equal 2000, discounts.rows.sole[4]
  end

  test "stock valuation agrees with the stock page, and dead stock lists what isn't selling" do
    valuation = report("stock_valuation")
    assert_equal StockValuation.new(Current.account).total_value_cents, valuation.sections.first.totals[2]

    sell(products(:acme_nails))
    dead = report("dead_stock", days: "30").sections.first.rows.map { _1.first.record }
    assert_includes dead, products(:acme_cement)
    assert_not_includes dead, products(:acme_nails)
  end

  test "shifts closed in the period with their over/short" do
    sell(products(:acme_nails), quantity: 4)
    @shift.close(counted_cash_cents: @shift.expected_cash_cents_now - 500)

    row = report("shifts").sections.first.rows.sole
    assert_equal [ 100000, 600000, 599500, -500 ], row.last(4)
  end

  test "another shop's sales never appear" do
    Current.account = accounts(:bolt)
    register = accounts(:bolt).registers.create!(branch: branches(:bolt_main), name: "Counter")
    shift = Shift.create!(account: accounts(:bolt), register: register, opening_float_cents: 0)
    sale = shift.current_sale
    sale.add(products(:bolt_hammer))
    sale.pay(tender: "cash")

    Current.account = accounts(:acme)
    assert_equal 0, report("sales").sections.first.totals[2]
  end

  test "periods from presets or dates, and CSV export" do
    period = Report::Period.from_params({ from: "2026-02-10", to: "2026-02-01" })
    assert_equal [ Date.new(2026, 2, 1), Date.new(2026, 2, 10) ], [ period.from, period.to ]
    assert_equal "last_week", Report::Period.from_params({ preset: "last_week", from: "2026-02-10" }).preset
    assert_equal Date.current.beginning_of_month, Report::Period.from_params({}).from

    sell(products(:acme_nails), quantity: 4)
    csv = CSV.parse(report("sales", by: "branch").to_csv)
    assert_equal [ "Main branch", "1", "1000.00" ], csv[3].first(3)
    assert_equal "Total", csv.last.first
  end
end
