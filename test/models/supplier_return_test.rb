require "test_helper"

class SupplierReturnTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @supplier = suppliers(:acme_cement_distributor)
    @main = branches(:acme_main)
    @cement = products(:acme_cement) # this supplier's last price 680.00 ex VAT, 16% VAT
  end

  def send_back(quantity: 3, **attributes)
    accounts(:acme).supplier_returns.create!({ supplier: @supplier, branch: @main, reason: "damaged",
      lines_attributes: [ { account: accounts(:acme), product: @cement, quantity: quantity } ] }.merge(attributes))
  end

  test "goods leave stock, and the debit note with VAT comes off what's owed, oldest invoice first" do
    invoice = @supplier.supplier_invoices.create!(account: accounts(:acme), number: "NCD-1", invoice_date: Date.current, total: "5000")
    stock = @cement.stock_at(@main)

    returned = send_back
    assert_equal "MAIN-SR00001", returned.reference
    assert_equal [ 680_00, 16 ], [ returned.lines.sole.unit_cost_cents, returned.lines.sole.tax_rate.to_i ], "the supplier's own last price"
    assert_equal [ 326_40, 2366_40 ], [ returned.tax_cents, returned.total_cents ], "3 × 680 = 2,040 + 16% VAT"
    assert_equal stock - 3, @cement.stock_at(@main)
    assert_equal "returned_to_supplier", @cement.stock_movements.last.reason
    assert_equal 5000_00 - 2366_40, @supplier.balance_cents
    assert_equal 5000_00 - 2366_40, @supplier.open_invoices.sole.outstanding_cents
    assert_equal invoice, @supplier.open_invoices.sole.invoice

    tax = Report::Tax.new(account: accounts(:acme), period: Report::Period.for_preset("today"))
    assert_equal(-326_40, tax.input_tax_cents)
    assert_match "1 debit note", tax.sections[1].rows.last.first
  end

  test "from a delivery, at what was paid; never more than is in stock" do
    order = accounts(:acme).purchase_orders.create!(supplier: @supplier, branch: @main, lines_attributes: [ { product_code: "CEM-50", quantity: 10, unit_cost: "650" } ]).tap(&:mark_sent)
    receipt = accounts(:acme).goods_receipts.create!(supplier: @supplier, branch: @main, purchase_order: order,
      lines_attributes: [ { purchase_order_line_id: order.lines.sole.id, quantity: 10 } ])
    assert_equal 650_00, send_back(goods_receipt: receipt).lines.sole.unit_cost_cents

    too_many = accounts(:acme).supplier_returns.new(supplier: @supplier, branch: @main, reason: "damaged",
      lines_attributes: [ { account: accounts(:acme), product: @cement, quantity: 1000 } ])
    assert_not too_many.valid?
    assert_match "more than", too_many.errors.full_messages.to_sentence
    assert_not accounts(:acme).supplier_returns.new(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_yard), goods_receipt: receipt, reason: "damaged",
      lines_attributes: [ { account: accounts(:acme), product: @cement, quantity: 1 } ]).valid?, "the delivery was to another branch"
  end

  test "a batch can be chosen; the supplier's credit note is noted" do
    @cement.update!(tracks_batches: true)
    @cement.move_stock(branch: @main, quantity: 5, reason: "received", batch: { number: "BAD-1", expires_on: 1.year.from_now.to_date })
    batch = @cement.stock_batches.find_by!(number: "BAD-1")
    returned = accounts(:acme).supplier_returns.create!(supplier: @supplier, branch: @main, reason: "faulty",
      lines_attributes: [ { account: accounts(:acme), product: @cement, quantity: 5, stock_batch: batch } ])
    assert_equal 0, batch.reload.quantity

    assert_not returned.record_credit_note(number: " ")
    assert returned.record_credit_note(number: "CN-7781", on: Date.yesterday)
    assert returned.reload.credited?
    assert_equal "credited", returned.events.last.action
  end

  test "suppliers in dollars: the debit note is in dollars, stock leaves at shillings" do
    accounts(:acme).currencies.create!(code: "USD", rate: 130, accepted_at_till: false)
    importer = accounts(:acme).suppliers.create!(name: "Guangzhou Tools", currency: "USD")
    returned = accounts(:acme).supplier_returns.create!(supplier: importer, branch: @main, reason: "wrong_item",
      lines_attributes: [ { account: accounts(:acme), product: @cement, quantity: 1, unit_cost: "5" } ])
    assert_equal [ "USD", 130, 580 ], [ returned.currency, returned.exchange_rate, returned.total_cents ]
    assert_equal 650_00, @cement.stock_movements.last.unit_cost_cents
    assert_equal(-580, importer.balance_cents)
  end
end
