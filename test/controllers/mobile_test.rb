require "test_helper"

class MobileTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def acme(&) = Account.without_isolation(&)
  def as_acme(&) = acme { Current.set(account: @account) { yield } }

  test "looking a product up by barcode, SKU and name" do
    get mobile_root_path
    assert_select "[data-controller=camera-scanner]"
    assert_select "link[rel=manifest][href=?]", pwa_stock_manifest_path(format: :json)

    get mobile_product_path("scan", code: "NAIL-3"), headers: { "Turbo-Frame" => "scan_result" }
    assert_response :success
    assert_select "turbo-frame#scan_result h2", products(:acme_nails).name
    assert_select "td", branches(:acme_main).name

    get mobile_product_path("scan", code: "NOPE-1"), headers: { "Turbo-Frame" => "scan_result" }
    assert_response :not_found
    assert_select "p", /Nothing found for “NOPE-1”/

    get mobile_products_path(query: "nails")
    assert_select "a[href=?]", mobile_product_path(products(:acme_nails))

    get pwa_stock_manifest_path(format: :json)
    assert_equal "/m", JSON.parse(response.body)["start_url"]
  end

  test "counting on the phone: blind, adding up from several places, or setting a total" do
    count = as_acme { @account.stock_counts.create!(branch: branches(:acme_main)) }
    line = acme { count.lines.find_by(product: products(:acme_nails)) }

    get mobile_stock_counts_path
    assert_select "a[href=?]", mobile_stock_count_path(count)
    get mobile_stock_count_path(count)
    assert_select "#count_progress", /0\s*of/

    get mobile_stock_count_count_lines_path(count, code: "NAIL-3"), headers: { "Turbo-Frame" => "scan_result" }
    assert_select "input[name=line_id][value=?]", line.id.to_s
    assert_no_match(/expect/i, css_select("turbo-frame").text, "counts are blind")

    post mobile_stock_count_count_entries_path(count), params: { line_id: line.id, quantity: "4", mode: "add" }, as: :turbo_stream
    post mobile_stock_count_count_entries_path(count), params: { line_id: line.id, quantity: "2.5", mode: "add" }, as: :turbo_stream
    assert_equal 6.5, acme { line.reload.counted_quantity }, "nails are counted by the kilo"
    assert_select "turbo-stream[target=count_progress]"

    post mobile_stock_count_count_entries_path(count), params: { line_id: line.id, quantity: "5", mode: "set" }, as: :turbo_stream
    assert_equal 5, acme { line.reload.counted_quantity }

    as_acme { count.submit }
    post mobile_stock_count_count_entries_path(count), params: { line_id: line.id, quantity: "1", mode: "add" }, as: :turbo_stream
    assert_response :conflict
  end

  test "receiving a delivery by scanning, then recording it" do
    order = as_acme do
      @account.purchase_orders.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
        lines_attributes: [ { product_code: "CEM-50", quantity: 10 } ]).tap(&:mark_sent)
    end
    order_line = acme { order.lines.sole }

    get mobile_purchase_orders_path
    assert_select "a[href=?]", mobile_purchase_order_path(order)

    get mobile_purchase_order_receipt_lines_path(order, code: "CEM-50"), headers: { "Turbo-Frame" => "scan_result" }
    assert_select "input[name=line_id][value=?]", order_line.id.to_s
    get mobile_purchase_order_receipt_lines_path(order, code: "NAIL-3"), headers: { "Turbo-Frame" => "scan_result" }
    assert_select "p", /isn't on this order/

    post mobile_purchase_order_receipt_entries_path(order), params: { line_id: order_line.id, quantity: "6", mode: "add" }, as: :turbo_stream
    post mobile_purchase_order_receipt_entries_path(order), params: { line_id: order_line.id, quantity: "6", mode: "add" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "Only 10", response.body

    stock_before = acme { products(:acme_cement).stock_at(branches(:acme_main)) }
    post mobile_purchase_order_goods_receipt_path(order), params: { supplier_reference: "DN-5521" }
    assert_redirected_to mobile_purchase_orders_path
    receipt = acme { @account.goods_receipts.last }
    assert_equal [ 6, "DN-5521" ], acme { [ receipt.lines.sole.quantity, receipt.supplier_reference ] }
    assert_equal stock_before + 6, acme { products(:acme_cement).stock_at(branches(:acme_main)) }
    assert acme { order.reload.partially_received? }

    post mobile_purchase_order_receipt_entries_path(order), params: { everything: 1 }
    post mobile_purchase_order_goods_receipt_path(order)
    assert acme { order.reload.received? }
  end

  test "cashiers can look up but not count or receive" do
    sign_in_as users(:carl), account: @account
    get mobile_root_path
    assert_response :success
    assert_select "nav a", text: "Count", count: 0
    get mobile_stock_counts_path
    assert_response :forbidden
    get mobile_purchase_orders_path
    assert_response :forbidden
  end
end
