require "test_helper"

class Etims::PurchaseTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Current.account = @acme = accounts(:acme)
    Current.session = @acme.sessions.create!(user: users(:amina))
    @main = branches(:acme_main)
    @device = @acme.etims_devices.create!(branch: @main, environment: "sandbox", tin: "P051234567X", serial_number: "HP-1", cmc_key: "KEY")
    @ncd = suppliers(:acme_cement_distributor).tap { _1.update!(tax_pin: "P051999888Z") }
    @kra = fake_transport(Etims::Client, "/etims-api/selectTrnsPurchaseSalesList" => ->(_) { @answer })
    @answer = { resultCd: "000", data: { saleList: [ cement_invoice ] } }
  end

  # 20 bags at 812 with VAT (700 before), 2 kg of nails nobody has matched yet, and transport.
  def cement_invoice(number: "NCD-7781")
    { spplrTin: "P051999888Z", spplrNm: "NAIROBI CEMENT DISTRIBUTORS LTD", spplrBhfId: "00", spplrInvcNo: number, rcptTyCd: "S", salesDt: "20261112", cfmDt: "20261112101500",
      totTaxblAmt: 20300, totTaxAmt: 2800, totAmt: 20300,
      itemList: [ { itemSeq: 1, itemCd: "NCD-BAM50", itemNm: "BAMBURI NGUVU 50KG", bcd: nil, qtyUnitCd: "BG", qty: 20, prc: 812, taxTyCd: "B", taxblAmt: 16240, taxAmt: 2240, totAmt: 16240 },
                  { itemSeq: 2, itemCd: "KE2NTKG0000911", itemNm: "Wire nails 3 inch", bcd: nil, qtyUnitCd: "KG", qty: 2, prc: 290, taxTyCd: "B", taxblAmt: 580, taxAmt: 80, totAmt: 580 },
                  { itemSeq: 3, itemCd: "KE3NTU0000001", itemNm: "TRANSPORT", qty: 1, prc: 3480, taxTyCd: "B", taxblAmt: 3480, taxAmt: 480, totAmt: 3480 } ] }
  end

  def fetched = Etims::Purchase.fetch(@device).then { @acme.etims_purchases.order(:id).last }

  test "new invoices are fetched once, with the supplier found by KRA PIN and each line costed before VAT" do
    assert_equal 1, Etims::Purchase.fetch(@device)
    assert_equal 0, Etims::Purchase.fetch(@device), "asked again, nothing is new"

    request = @kra.requests.first
    assert_equal [ "P051234567X", "00", "KEY" ], request.headers.values_at("tin", "bhfId", "cmcKey")
    assert_match(/\A\d{14}\z/, request.json[:lastReqDt])
    assert_operator Time.find_zone("Nairobi").strptime(@kra.requests.last.json[:lastReqDt], "%Y%m%d%H%M%S"), :<, 23.hours.ago, "the second time, from a day before the first"

    purchase = @acme.etims_purchases.sole
    assert_equal [ @ncd, "NCD-7781", Date.new(2026, 11, 12), 2_030_000, 280_000, "new" ],
      [ purchase.supplier, purchase.invoice_number, purchase.sales_date, purchase.total_cents, purchase.tax_cents, purchase.status ]
    assert_equal [ [ "BAMBURI NGUVU 50KG", 20, 70_000 ], [ "Wire nails 3 inch", 2, 25_000 ], [ "TRANSPORT", 1, 300_000 ] ], purchase.lines.map { [ _1.name, _1.quantity.to_i, _1.unit_cost_cents ] }
    assert @device.reload.purchases_checked_at
  end

  test "lines are matched by the supplier's code, by name and by barcode; what matches nothing is left for a person" do
    purchase = fetched
    assert_equal [ products(:acme_cement), products(:acme_nails), nil ], purchase.suggested_products.values_at(1, 2, 3)

    @answer[:data][:saleList] = [ cement_invoice(number: "NCD-7790").merge(itemList: [ { itemSeq: 1, itemNm: "Something else", bcd: "6161100420017", qty: 1, taxAmt: 0, totAmt: 100 } ]) ]
    assert_equal products(:acme_cement), fetched.suggested_products[1], "the barcode on the invoice is the cement's"
  end

  test "receiving puts the goods into stock at their cost before VAT and records the invoice against the delivery" do
    purchase = fetched
    assert_not purchase.receive, "the transport line matches no product"
    assert_match "Say which product “TRANSPORT” is (line 3), or leave it out", purchase.errors.full_messages.to_sentence
    assert purchase.reload.new?
    assert_equal 0, @acme.goods_receipts.count

    assert_difference -> { products(:acme_cement).stock_at(@main) } => 20, -> { products(:acme_nails).stock_at(@main) } => 2 do
      assert purchase.receive({ "3" => { skip: "1" } }), purchase.errors.full_messages.to_sentence
    end

    receipt = purchase.goods_receipt
    assert_equal [ @ncd, @main, "NCD-7781", 2 ], [ receipt.supplier, receipt.branch, receipt.supplier_reference, receipt.lines.size ]
    assert_equal [ 70_000, 25_000 ], receipt.lines.order(:id).map(&:unit_cost_cents)
    assert_equal "received", products(:acme_cement).stock_movements.order(:id).last.reason

    invoice = purchase.supplier_invoice
    assert_equal [ "NCD-7781", Date.new(2026, 11, 12), 2_030_000, 280_000, receipt, Date.new(2026, 12, 12) ],
      [ invoice.number, invoice.invoice_date, invoice.total_cents, invoice.tax_cents, invoice.goods_receipt, invoice.due_date ]
    assert_equal [ "received", users(:amina) ], [ purchase.status, purchase.handled_by ]

    assert_not purchase.receive({ "3" => { skip: "1" } }), "not twice"
    assert_match "already been received", purchase.errors.full_messages.to_sentence
    assert_equal 1, @acme.goods_receipts.count
  end

  test "a line pointed at a product by hand is remembered for the supplier's next invoice" do
    wire = @acme.products.create!(name: "Binding wire", sku: "BW-25", unit: units(:acme_kg), price_cents: 30000)
    first = fetched
    assert first.receive({ "2" => { product_code: "bw-25", quantity: "2", unit_cost: "240" }, "3" => { skip: "1" } }), first.errors.full_messages.to_sentence
    assert_equal [ 2, 24_000 ], first.goods_receipt.lines.find_by!(product: wire).then { [ _1.quantity.to_i, _1.unit_cost_cents ] }

    @answer[:data][:saleList] = [ cement_invoice(number: "NCD-7802") ]
    assert_equal wire, fetched.suggested_products[2], "last time this supplier's line was the binding wire, whatever its name says"
  end

  test "a wrong code stops everything, and nothing is half received" do
    purchase = fetched
    assert_not purchase.receive({ "1" => { product_code: "NOPE" }, "3" => { skip: "1" } })
    assert_match "No product with barcode or SKU “NOPE” (line 1, BAMBURI NGUVU 50KG)", purchase.errors.full_messages.to_sentence
    assert_equal [ 0, 0 ], [ @acme.goods_receipts.count, @acme.supplier_invoices.count ]
  end

  test "an unknown supplier is added from KRA's details when the invoice is recorded" do
    @answer[:data][:saleList] = [ cement_invoice.merge(spplrTin: "P052777666K", spplrNm: "Rift Valley Steel Mills Ltd") ]
    purchase = fetched
    assert_nil purchase.supplier

    assert purchase.record_invoice, purchase.errors.full_messages.to_sentence
    supplier = purchase.supplier
    assert_equal [ "Rift Valley Steel Mills Ltd", "P052777666K" ], [ supplier.name, supplier.tax_pin ]
    assert_equal [ "invoiced", nil, 2_030_000 ], [ purchase.status, purchase.goods_receipt, supplier.supplier_invoices.sole.total_cents ]
  end

  test "an invoice only can be put against a delivery already received" do
    receipt = @acme.goods_receipts.create!(supplier: @ncd, branch: @main, lines_attributes: [ { account: @acme, product_code: "CEM-50", quantity: 25, unit_cost: "700" } ])
    purchase = fetched
    assert purchase.record_invoice(goods_receipt: receipt)
    assert_equal receipt, purchase.supplier_invoice.goods_receipt
  end

  test "an invoice already typed in by hand is not offered again" do
    @ncd.supplier_invoices.create!(account: @acme, number: "ncd-7781", invoice_date: Date.new(2026, 11, 12), total: "20300")
    purchase = fetched
    assert_equal [ "invoiced", "Already recorded by hand" ], [ purchase.status, purchase.note ]
    assert_equal 0, @acme.etims_purchases.waiting.count
  end

  test "setting aside and bringing back; credit notes are never received" do
    purchase = fetched
    assert purchase.dismiss(reason: "For the Mombasa shop")
    assert_equal [ "dismissed", "For the Mombasa shop" ], [ purchase.status, purchase.note ]
    assert_not purchase.receive({ "3" => { skip: "1" } })
    assert purchase.restore
    assert purchase.new?

    @answer[:data][:saleList] = [ cement_invoice(number: "NCD-CN-4").merge(rcptTyCd: "R") ]
    credit = fetched
    assert credit.credit_note?
    assert_not credit.record_invoice
    assert_match "credit note", credit.errors.full_messages.to_sentence
  end

  test "no invoices, a refusal and KRA being down are all answers, not errors" do
    @answer = { resultCd: "001", resultMsg: "There is no search result" }
    assert_equal 0, Etims::Purchase.fetch(@device)
    assert_nil @device.reload.purchases_error

    checked = @device.purchases_checked_at
    @answer = { resultCd: "901", resultMsg: "It is not valid device" }
    assert_equal 0, Etims::Purchase.fetch(@device)
    assert_equal [ "901: It is not valid device", checked ], @device.reload.then { [ _1.purchases_error, _1.purchases_checked_at ] }, "asked again from the same time tomorrow"

    @answer = JsonHttp::Unreachable.new("execution expired")
    assert_equal 0, Etims::Purchase.fetch(@device)
    assert_equal "execution expired", @device.reload.purchases_error
  end

  test "the morning's job asks for every shop with a control unit set up, each in its own job" do
    Current.reset
    assert_enqueued_with(job: Etims::PurchasesJob, args: [ @acme ]) { Etims::PurchasesJob.perform_now }
    Etims::PurchasesJob.perform_now(@acme)
    assert_equal 1, Account.without_isolation { Etims::Purchase.where(account_id: @acme.id).count }
  end

  test "the simulator makes up invoices from the shop's own catalogue, once a day" do
    @device.update!(environment: "simulator")
    assert_equal 2, Etims::Purchase.fetch(@device)
    assert_equal 0, Etims::Purchase.fetch(@device)
    known, stranger = @acme.etims_purchases.order(:id).to_a
    assert_equal [ @ncd, products(:acme_cement) ], [ known.supplier, known.suggested_products[1] ]
    assert_equal known.lines.sum(&:total_cents), known.total_cents
    assert_nil stranger.supplier
  end
end
