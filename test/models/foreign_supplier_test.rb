require "test_helper"

class ForeignSupplierTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @account = accounts(:acme)
    @account.currencies.create!(code: "USD", rate: 130, accepted_at_till: false)
    @importer = @account.suppliers.create!(name: "Guangzhou Tools Export", currency: "usd", payment_terms_days: 60)
    @drill = products(:acme_screws)
  end

  def order(quantity: 100, unit_cost: "2.50")
    @account.purchase_orders.create!(supplier: @importer, branch: branches(:acme_main), lines_attributes: [ { product_code: @drill.sku, quantity: quantity, unit_cost: unit_cost } ]).tap(&:mark_sent)
  end

  test "orders are in the supplier's currency, and keep the rate of the day" do
    po = order
    assert_equal "USD", po.currency
    assert_equal 250_00, po.total_cents
    assert_equal 130, po.exchange_rate

    default = @account.purchase_orders.create!(supplier: @importer, branch: branches(:acme_main), lines_attributes: [ { product_code: @drill.sku, quantity: 1 } ])
    assert_equal (@drill.cost_cents / 130.0).ceil, default.lines.sole.unit_cost_cents, "a product's cost, converted"
  end

  test "receiving converts at the receipt's rate, with transport paid here" do
    po = order
    receipt = @account.goods_receipts.create!(supplier: @importer, branch: branches(:acme_main), purchase_order: po, exchange_rate: 132, extra_costs: "1000",
      lines_attributes: [ { purchase_order_line_id: po.lines.sole.id, quantity: 100 } ])

    assert_equal 2_50, receipt.lines.sole.unit_cost_cents, "USD 2.50, as on the supplier's invoice"
    assert_equal 330_00 + 10_00, receipt.lines.sole.landed_unit_cost_cents, "USD 2.50 × 132 + KES 1,000 over 100"
    assert_equal 33_000_00 + 1000_00, receipt.total_cents
  end

  test "invoices and payments in dollars; totals, VAT and the payables convert" do
    invoice = @importer.supplier_invoices.create!(account: @account, number: "GZ-88", invoice_date: Date.current, total: "1160", tax: "160")
    assert_equal 130, invoice.exchange_rate
    @importer.supplier_payments.create!(account: @account, paid_on: Date.current, amount: "160", payment_method: "bank_transfer")

    assert_equal 1000_00, @importer.balance_cents, "owed in USD"
    assert_equal 130_000_00, @importer.to_base_cents(@importer.balance_cents)

    tax = Report::Tax.new(account: @account, period: Report::Period.for_preset("today"))
    assert_equal 160_00 * 130, tax.input_tax_cents

    @importer.currency = nil
    assert_not @importer.valid?
    assert_match "can't change", @importer.errors.full_messages.to_sentence
  end

  test "a supplier's currency must be one of the shop's" do
    assert_not @account.suppliers.new(name: "Euro Fittings", currency: "EUR").valid?
  end
end
