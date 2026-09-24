require "test_helper"

class PurchasingTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:sara))
  end

  def order(lines, supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main))
    accounts(:acme).purchase_orders.create!(supplier: supplier, branch: branch, lines_attributes: lines)
  end

  test "orders are numbered per branch and default to the supplier's cost" do
    po = order([ { product_code: "CEM-50", quantity: 100 } ])

    assert_equal "MAIN-PO00001", po.reference
    assert_equal 68000, po.lines.sole.unit_cost_cents
    assert_equal 6_800_000, po.total_cents
    assert po.draft?
  end

  test "untracked products and unknown codes can't be ordered" do
    assert_raises(ActiveRecord::RecordInvalid) { order([ { product_code: "KIT-PLB", quantity: 1 } ]) }
    assert_raises(ActiveRecord::RecordInvalid) { order([ { product_code: "HAM-16", quantity: 1 } ]) }
  end

  test "receiving part of an order, then the rest" do
    po = order([ { product_code: "CEM-50", quantity: 100 } ])
    po.mark_sent
    line = po.lines.sole

    accounts(:acme).goods_receipts.create!(supplier: po.supplier, branch: po.branch, purchase_order: po,
      lines_attributes: [ { purchase_order_line_id: line.id, quantity: 60 } ])
    assert po.reload.partially_received?
    assert_equal 110, products(:acme_cement).stock_at(branches(:acme_main))

    too_many = accounts(:acme).goods_receipts.new(supplier: po.supplier, branch: po.branch, purchase_order: po,
      lines_attributes: [ { purchase_order_line_id: line.id, quantity: 41 } ])
    assert_not too_many.valid?
    assert_match "Only 40", too_many.errors.full_messages.to_sentence

    accounts(:acme).goods_receipts.create!(supplier: po.supplier, branch: po.branch, purchase_order: po,
      lines_attributes: [ { purchase_order_line_id: line.id, quantity: 40 } ])
    assert po.reload.received?
    assert_not po.receivable?
  end

  test "receiving updates the weighted-average cost" do
    # 60 bags on hand at 700.00; 40 more arrive at 750.00 → (60×700 + 40×750) / 100 = 720.00
    accounts(:acme).goods_receipts.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
      lines_attributes: [ { product_code: "CEM-50", quantity: 40, unit_cost: "750" } ])

    assert_equal 72000, products(:acme_cement).reload.cost_cents
    assert_equal 75000, supplier_products(:acme_cement_from_ncd).reload.cost_cents, "remembers the supplier's latest price"
    assert_equal "received", StockMovement.where(product: products(:acme_cement)).order(:id).last.reason
  end

  test "transport and duty are spread over the lines by value" do
    grn = accounts(:acme).goods_receipts.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_yard),
      extra_costs: "3000", lines_attributes: [
        { product_code: "CEM-50", quantity: 20, unit_cost: "700" },   # 14,000 of 20,000 → 2,100 extra → +105/bag
        { product_code: "PVC-2", quantity: 5, unit_cost: "1200" }     # 6,000 of 20,000 → 900 extra → +180/pipe
      ])

    landed = grn.lines.to_h { [ _1.product.sku, _1.landed_unit_cost_cents ] }
    assert_equal({ "CEM-50" => 80500, "PVC-2" => 138000 }, landed)
    assert_equal 2_300_000, grn.total_cents
  end

  test "a receipt must match its order's supplier and branch" do
    po = order([ { product_code: "CEM-50", quantity: 10 } ])
    po.mark_sent
    grn = accounts(:acme).goods_receipts.new(supplier: suppliers(:acme_plumbing_supplies), branch: branches(:acme_yard), purchase_order: po,
      lines_attributes: [ { purchase_order_line_id: po.lines.sole.id, quantity: 1 } ])

    assert_not grn.valid?
    assert_includes grn.errors[:purchase_order], "is for another supplier"
    assert_includes grn.errors[:purchase_order], "is for another branch"
  end

  test "drafts can't be received and sent orders can't be edited" do
    po = order([ { product_code: "CEM-50", quantity: 10 } ])
    grn = accounts(:acme).goods_receipts.new(supplier: po.supplier, branch: po.branch, purchase_order: po,
      lines_attributes: [ { purchase_order_line_id: po.lines.sole.id, quantity: 1 } ])
    assert_not grn.valid?

    po.mark_sent
    assert_not po.update(lines_attributes: [ { id: po.lines.sole.id, quantity: 99 } ])
  end

  test "payments settle the oldest invoices first, and ageing follows due dates" do
    supplier = suppliers(:acme_cement_distributor)
    travel_to Date.new(2026, 9, 24) do
      supplier.supplier_invoices.create!(account: accounts(:acme), number: "INV-1", invoice_date: Date.new(2026, 6, 1), total: "100000")  # due 1 Jul
      supplier.supplier_invoices.create!(account: accounts(:acme), number: "INV-2", invoice_date: Date.new(2026, 8, 1), total: "50000")   # due 31 Aug
      supplier.supplier_invoices.create!(account: accounts(:acme), number: "inv-3", invoice_date: Date.new(2026, 9, 20), total: "20000")  # due 20 Oct
      supplier.supplier_payments.create!(account: accounts(:acme), paid_on: Date.current, amount: "70000", payment_method: "bank_transfer")

      assert_equal 10_000_000, supplier.balance_cents
      assert_equal [ [ "INV-1", 3_000_000 ], [ "INV-2", 5_000_000 ], [ "INV-3", 2_000_000 ] ],
        supplier.open_invoices.map { [ _1.invoice.number, _1.outstanding_cents ] }
      assert_equal({ "current" => 2_000_000, "1_30" => 5_000_000, "31_60" => 0, "61_90" => 3_000_000, "over_90" => 0 }, supplier.ageing)
    end
  end

  test "an invoice number is recorded once per supplier" do
    supplier = suppliers(:acme_cement_distributor)
    supplier.supplier_invoices.create!(account: accounts(:acme), number: "A1", invoice_date: Date.current, total: "1")
    assert_not supplier.supplier_invoices.new(account: accounts(:acme), number: "a1", invoice_date: Date.current, total: "1").valid?
  end

  test "reorder suggestions use reorder levels, sales, lead time, what's on order and minimum order sizes" do
    # PVC pipe: 3 on hand, reorder at 5, minimum order of 5 → wants 10, needs 7, rounded up to 10
    # Cement: 50 on hand but selling 3 bags a day with a 3-day lead time → wants 3 × 17 = 51... still covered
    30.times { products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -3, reason: "sold") }
    # Cement now 50 − 90 = −40 → wants max(40, 3 × 17 = 51) → needs 91 → rounded to 100 in tens
    suggestion = ReorderSuggestion.new(accounts(:acme), branches(:acme_main))
    rows = suggestion.rows.to_h { [ _1.product.sku, _1.quantity ] }

    assert_equal 10, rows["PVC-2"]
    assert_equal 100, rows["CEM-50"]
    assert_equal [ suppliers(:acme_plumbing_supplies), suppliers(:acme_cement_distributor) ], suggestion.by_supplier.map(&:first).compact

    order([ { product_code: "PVC-2", quantity: 10 } ], supplier: suppliers(:acme_plumbing_supplies)).mark_sent
    assert_nil ReorderSuggestion.new(accounts(:acme), branches(:acme_main)).rows.find { _1.product.sku == "PVC-2" }, "already on order"
  end

  test "the order renders as a PDF" do
    products(:acme_pipe).update!(name: "PVC pipe 2½ inch × 6m")
    po = order([ { product_code: "CEM-50", quantity: 100 }, { product_code: "PVC-2", quantity: 4 } ])
    pdf = PurchaseOrderPdf.new(po).render

    assert pdf.start_with?("%PDF")
    assert_operator pdf.bytesize, :>, 1000
  end
end
