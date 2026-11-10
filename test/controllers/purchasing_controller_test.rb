require "test_helper"

class PurchasingControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:sara) } # stock clerk

  def new_order(lines = { "0" => { product_code: "CEM-50", quantity: "100" }, "1" => { product_code: "", quantity: "" } })
    post purchase_orders_path, params: { purchase_order: { supplier_id: suppliers(:acme_cement_distributor).id, branch_id: branches(:acme_main).id,
      expected_on: 3.days.from_now.to_date, lines_attributes: lines } }
    Account.without_isolation { PurchaseOrder.last }
  end

  test "draft, edit, email to the supplier with the PDF, receive in two deliveries" do
    order = new_order
    assert_redirected_to purchase_order_path(order)
    assert_equal 6_800_000, order.total_cents

    line = Account.without_isolation { order.lines.sole }
    patch purchase_order_path(order), params: { purchase_order: { lines_attributes: {
      "0" => { id: line.id, quantity: "80" }, "1" => { product_code: "PVC-2", quantity: "4", unit_cost: "900" } } } }
    assert_equal [ 80, 4 ], Account.without_isolation { order.reload.lines.map { _1.quantity.to_i } }

    get purchase_order_path(order, format: :pdf)
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")

    perform_enqueued_jobs { post purchase_order_sending_path(order), params: { email: "1" } }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "orders@ncd.test" ], mail.to
    assert_equal "MAIN-PO00001.pdf", mail.attachments.sole.filename
    assert Account.without_isolation { order.reload.sent? }

    get new_goods_receipt_path(purchase_order_id: order.id)
    assert_select "input[name*=quantity]", 2

    cement_line, pipe_line = Account.without_isolation { order.lines.to_a }
    post goods_receipts_path, params: { goods_receipt: { purchase_order_id: order.id, supplier_reference: "DN-5521", lines_attributes: {
      "0" => { purchase_order_line_id: cement_line.id, quantity: "50", unit_cost: "680" },
      "1" => { purchase_order_line_id: pipe_line.id, quantity: "0", unit_cost: "900" } } } }
    assert Account.without_isolation { order.reload.partially_received? }
    assert_equal 100, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_main)) }

    post goods_receipts_path, params: { goods_receipt: { purchase_order_id: order.id, lines_attributes: {
      "0" => { purchase_order_line_id: cement_line.id, quantity: "30", unit_cost: "680" },
      "1" => { purchase_order_line_id: pipe_line.id, quantity: "4", unit_cost: "900" } } } }
    assert Account.without_isolation { order.reload.received? }
  end

  test "packs on the order and receiving forms, in packs; stock in pieces" do
    order = new_order({ "0" => { product_code: "SCR-815", pack: "box", quantity: "3", unit_cost: "400" } })
    assert_equal 300, Account.without_isolation { order.lines.sole.quantity }

    get edit_purchase_order_path(order)
    assert_select "input[name*='[pack]'][value='box']"
    assert_select "input[name*='[quantity]'][value='3']"
    assert_select "input[name*='[unit_cost]'][value='400']"

    post purchase_order_sending_path(order)
    get new_goods_receipt_path(purchase_order_id: order.id)
    assert_select "input[name*='[pack]'][value='box']"
    assert_select "input[name*='[quantity]'][value='3']"

    get purchase_order_path(order)
    assert_select "td", /3 box/
  end

  test "a partly delivered order is closed short from its page" do
    order = new_order
    post purchase_order_sending_path(order)
    line = Account.without_isolation { order.lines.sole }
    post goods_receipts_path, params: { goods_receipt: { purchase_order_id: order.id, lines_attributes: { "0" => { purchase_order_line_id: line.id, quantity: "60" } } } }

    get purchase_order_path(order)
    assert_select "button", "Close short"

    post purchase_order_closure_path(order)
    assert_redirected_to purchase_order_path(order)
    assert Account.without_isolation { order.reload.closed? }

    get purchase_order_path(order)
    assert_select "td", /40 short/
    assert_select "button", text: "Close short", count: 0
    assert_select "a", text: "Receive goods", count: 0
  end

  test "purchase orders are searched by supplier" do
    reference = Account.without_isolation { new_order.reference }

    get purchase_orders_path(query: "Nairobi")
    assert_select "td a", reference
    assert_select "form[role=search] span", text: "Search: Nairobi"

    get purchase_orders_path(query: "Kentube")
    assert_select "td a", text: reference, count: 0
  end

  test "purchase orders grouped by supplier and by status, with totals in the supplier's currency" do
    new_order

    get purchase_orders_path(group_by: "supplier")
    assert_select "details summary", text: /Nairobi Cement Distributors\s*\(1\)\s*KES 68,000.00/

    get purchase_orders_path(group_by: "status")
    assert_select "details summary", text: /Draft\s*\(1\)\s*KES 68,000.00/
  end

  test "sent orders can't be edited" do
    order = new_order
    post purchase_order_sending_path(order)
    line = Account.without_isolation { order.lines.sole }

    patch purchase_order_path(order), params: { purchase_order: { lines_attributes: { "0" => { id: line.id, quantity: "1" } } } }
    assert_response :unprocessable_entity
    assert_equal 100, Account.without_isolation { line.reload.quantity }
  end

  test "receiving without an order, with transport shared out" do
    post goods_receipts_path, params: { goods_receipt: { supplier_id: suppliers(:acme_plumbing_supplies).id, branch_id: branches(:acme_yard).id,
      extra_costs: "500", lines_attributes: { "0" => { product_code: "PVC-2", quantity: "5", unit_cost: "900" }, "1" => { product_code: "", quantity: "" } } } }

    receipt = Account.without_isolation { GoodsReceipt.last }
    assert_redirected_to goods_receipt_path(receipt)
    assert_equal 100000, Account.without_isolation { receipt.lines.sole.landed_unit_cost_cents }, "900 + 500 transport ÷ 5 pipes"
    assert_equal 5, Account.without_isolation { products(:acme_pipe).stock_at(branches(:acme_yard)) }
  end

  test "reorder suggestions draft an order in one click" do
    get reorder_suggestions_path(branch_id: branches(:acme_main).id)
    assert_redirected_to reorder_list_path(branch_id: branches(:acme_main).id)

    get reorder_list_path(branch_id: branches(:acme_main).id)
    assert_select "h2", /Kentube Plumbing Supplies/
    assert_select "td", "PVC pipe 2 inch 6m"

    post purchase_orders_path, params: { from_suggestions: 1, supplier_id: suppliers(:acme_plumbing_supplies).id, branch_id: branches(:acme_main).id }
    order = Account.without_isolation { PurchaseOrder.last }
    assert order.draft?
    assert_equal [ [ "PVC-2", 10 ] ], Account.without_isolation { order.lines.map { [ _1.product.sku, _1.quantity.to_i ] } }
  end

  test "Reorder drafts one order per supplier in one click" do
    get reorder_list_path(branch_id: branches(:acme_yard).id)
    assert_select "button", "Draft 2 purchase orders"

    assert_difference -> { Account.without_isolation { PurchaseOrder.draft.count } }, 2 do
      post purchase_orders_path, params: { from_suggestions: 1, supplier_id: "all", branch_id: branches(:acme_yard).id }
    end
    assert_redirected_to purchase_orders_path(status: "draft")
    orders = Account.without_isolation { PurchaseOrder.draft.includes(lines: :product).last(2).to_h { [ _1.supplier, _1.lines.map { |line| line.product.sku } ] } }
    assert_equal({ suppliers(:acme_cement_distributor) => [ "CEM-50" ], suppliers(:acme_plumbing_supplies) => [ "PVC-2" ] }, orders)
  end

  test "supplier products are managed on the supplier page" do
    post supplier_products_path(suppliers(:acme_plumbing_supplies)), params: { supplier_product: { product_code: "NAIL-3", cost: "170", lead_time_days: "2", min_order_quantity: "25" } }
    supplier_product = Account.without_isolation { suppliers(:acme_plumbing_supplies).supplier_products.find_by!(product: products(:acme_nails)) }

    patch supplier_product_path(suppliers(:acme_plumbing_supplies), supplier_product), params: { supplier_product: { cost: "165", preferred: "1" } }
    assert_equal [ 16500, true ], Account.without_isolation { supplier_product.reload.values_at(:cost_cents, :preferred) }
  end

  test "another shop's suppliers and orders are out of reach" do
    get supplier_path(suppliers(:bolt_supplier))
    assert_response :not_found

    post purchase_orders_path, params: { purchase_order: { supplier_id: suppliers(:bolt_supplier).id, branch_id: branches(:acme_main).id,
      lines_attributes: { "0" => { product_code: "CEM-50", quantity: "1" } } } }
    assert_response :not_found
  end

  test "cashiers can't purchase" do
    sign_in_as users(:carl)
    get purchase_orders_path
    assert_response :forbidden
    get suppliers_path
    assert_response :forbidden
  end

  test "a stock clerk bound to the yard can't receive goods into the main branch" do
    order = new_order
    Account.without_isolation { Current.set(account: accounts(:acme), user: users(:sara)) { order.mark_sent } }
    Account.without_isolation { memberships(:sara_acme).update!(branch: branches(:acme_yard)) }
    receipts = -> { Account.without_isolation { GoodsReceipt.count } }

    assert_no_difference receipts do
      post goods_receipts_path, params: { goods_receipt: { supplier_id: suppliers(:acme_plumbing_supplies).id, branch_id: branches(:acme_main).id,
        lines_attributes: { "0" => { product_code: "PVC-2", quantity: "5", unit_cost: "900" } } } }
      assert_response :not_found

      get new_goods_receipt_path(purchase_order_id: order.id)
      assert_select "input[value=?]", Account.without_isolation { order.lines.first.id.to_s }, count: 0
      post goods_receipts_path, params: { goods_receipt: { purchase_order_id: order.id,
        lines_attributes: { "0" => { purchase_order_line_id: Account.without_isolation { order.lines.first.id }, quantity: "5" } } } }
      assert_response :not_found
    end
  end
end

class PayablesControllerTest < ActionDispatch::IntegrationTest
  test "an accountant records invoices and payments and sees what's owed, but can't order" do
    Account.without_isolation { memberships(:carl_acme).update!(role: :accountant) }
    sign_in_as users(:carl)

    get purchase_orders_path
    assert_response :forbidden

    post supplier_invoices_path, params: { supplier_invoice: { supplier_id: suppliers(:acme_cement_distributor).id, number: "ncd-771",
      invoice_date: 45.days.ago.to_date, total: "120000", tax: "16551.72" } }
    assert_redirected_to supplier_path(suppliers(:acme_cement_distributor))

    post supplier_payments_path(suppliers(:acme_cement_distributor)), params: { supplier_payment: { amount: "20000", paid_on: Date.current, payment_method: "mobile_money", reference: "SJ81K" } }
    assert_redirected_to supplier_path(suppliers(:acme_cement_distributor))

    get payables_path
    assert_select "td", /KES 100,000.00/
    assert_select "td.text-red-700", /KES 100,000.00/, "15 days past its 30-day terms"

    get supplier_path(suppliers(:acme_cement_distributor))
    assert_select "td", /NCD-771/
  end

  test "the invoice for a delivery starts from its goods value and warns when it differs" do
    Account.without_isolation { memberships(:carl_acme).update!(role: :accountant) }
    sign_in_as users(:carl)
    receipt = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).goods_receipts.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main), extra_costs: "3000",
          lines_attributes: [ { product_code: "CEM-50", quantity: 20, unit_cost: "700" } ])
      end
    end

    get new_supplier_invoice_path(goods_receipt_id: receipt.id)
    assert_select "input[name='supplier_invoice[total]'][value='14000']", true, "the goods, not the landed total with the shop's own transport"

    post supplier_invoices_path, params: { supplier_invoice: { supplier_id: suppliers(:acme_cement_distributor).id, goods_receipt_id: receipt.id, number: "NCD-9", invoice_date: Date.current, total: "17000" } }
    follow_redirect!
    assert_select "#alert", /KES 3,000.00 more than the goods on MAIN-GRN00001/

    post supplier_invoices_path, params: { supplier_invoice: { supplier_id: suppliers(:acme_cement_distributor).id, goods_receipt_id: receipt.id, number: "NCD-10", invoice_date: Date.current, total: "14000" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /already has an invoice/
  end
end
