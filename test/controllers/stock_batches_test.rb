require "test_helper"

class StockBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
    @cement = products(:acme_cement)
    @batch = as_acme do
      @cement.update!(tracks_batches: true)
      @cement.move_stock(branch: branches(:acme_main), quantity: 12, reason: "received", batch: { number: "X-1", expires_on: 3.days.ago.to_date })
      @cement.stock_batches.find_by!(number: "X-1")
    end
  end

  def acme(&) = Account.without_isolation(&)
  def as_acme(&) = acme { Current.set(account: @account, user: users(:amina)) { yield } }

  test "the expiry list, a batch, and writing it off" do
    get stock_batches_path(branch_id: branches(:acme_main).id)
    assert_select "##{dom_id(@batch)}", /Expired/

    get stock_batch_path(@batch)
    assert_select "h1", /X-1/
    post stock_batch_write_off_path(@batch), params: { quantity: "12", reason: "expired", note: "Back to supplier" }
    assert_redirected_to stock_batch_path(@batch)
    assert_equal 0, acme { @batch.reload.quantity }

    post stock_batch_write_off_path(@batch), params: { quantity: "1" }
    assert_match "between 0", flash[:alert]

    get product_path(@cement)
    assert_select "section", /Batches in stock/
    get stock_path
    assert_select "a[href=?]", stock_batches_path
  end

  test "receiving a batch-tracked product on the desktop and the phone" do
    order = as_acme do
      @account.purchase_orders.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
        lines_attributes: [ { product_code: "CEM-50", quantity: 10 } ]).tap(&:mark_sent)
    end
    line = acme { order.lines.sole }

    get new_goods_receipt_path(purchase_order_id: order.id)
    assert_select "input[name*=batch_number][required]"
    post goods_receipts_path, params: { goods_receipt: { purchase_order_id: order.id, lines_attributes: { "0" => { purchase_order_line_id: line.id, quantity: "4", batch_number: "d-7", expires_on: 1.year.from_now.to_date } } } }
    assert_equal 4, acme { @cement.stock_batches.find_by!(number: "D-7").quantity }

    get mobile_purchase_order_receipt_lines_path(order, code: "CEM-50"), headers: { "Turbo-Frame" => "scan_result" }
    assert_select "input[name=batch_number]"
    post mobile_purchase_order_receipt_entries_path(order), params: { line_id: line.id, quantity: "3", mode: "add" }, as: :turbo_stream
    assert_match "batch number", response.body
    post mobile_purchase_order_receipt_entries_path(order), params: { line_id: line.id, quantity: "3", mode: "add", batch_number: "p-9", expires_on: "2027-06-30" }, as: :turbo_stream
    post mobile_purchase_order_receipt_entries_path(order), params: { line_id: line.id, quantity: "1", mode: "add", batch_number: "p-10" }, as: :turbo_stream
    assert_match "Record this delivery first", response.body
    post mobile_purchase_order_goods_receipt_path(order)
    phone_batch = acme { @cement.stock_batches.find_by!(number: "P-9") }
    assert_equal [ 3, Date.new(2027, 6, 30) ], [ phone_batch.quantity, phone_batch.expires_on ]
  end

  test "a sale shows the batches it took" do
    sale = as_acme do
      shifts(:acme_front_open).current_sale.tap do |sale|
        sale.add(@cement, quantity: @cement.unbatched_stock_at(branches(:acme_main)) + 2)
        sale.pay(tender: "card", reference: "VISA 1")
      end
    end
    get sale_path(sale)
    assert_match "batch X-1", response.body
  end
end
