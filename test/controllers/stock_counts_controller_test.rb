require "test_helper"

class StockCountsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:sara) }

  test "a stock clerk counts, a manager approves" do
    post stock_counts_path, params: { stock_count: { branch_id: branches(:acme_main).id, category_id: categories(:acme_fasteners).id } }
    count = Account.without_isolation { StockCount.last }
    assert_redirected_to stock_count_path(count)

    post stock_count_scan_path(count), params: { code: "NAIL-3", counted_quantity: "24" }
    line = Account.without_isolation { count.lines.find_by!(product: products(:acme_screws)) }
    patch stock_count_line_path(count, line), params: { stock_count_line: { counted_quantity: "1000" } }, as: :turbo_stream
    assert_response :success

    post stock_count_submission_path(count)
    post stock_count_approval_path(count)
    assert_response :forbidden, "stock clerks can't approve their own count"

    sign_in_as users(:amina)
    post stock_count_approval_path(count)
    assert_redirected_to stock_count_path(count)

    assert_equal 24, Account.without_isolation { products(:acme_nails).stock_at(branches(:acme_main)) }
    assert_equal 1000, Account.without_isolation { products(:acme_screws).stock_at(branches(:acme_main)) }
  end

  test "batch-tracked products are counted batch by batch, on the page or by scanning with the batch number" do
    Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        cement = products(:acme_cement)
        cement.update!(tracks_batches: true)
        cement.move_stock(branch: branches(:acme_main), quantity: 5, reason: "received", batch: { number: "A1", expires_on: 30.days.from_now.to_date })
      end
    end
    post stock_counts_path, params: { stock_count: { branch_id: branches(:acme_main).id, category_id: categories(:acme_building).id } }
    count = Account.without_isolation { StockCount.last }
    line = Account.without_isolation { count.lines.find_by!(product: products(:acme_cement)) }
    get stock_count_path(count)
    assert_select "##{dom_id(line)} input[aria-label=?]", "Counted #{products(:acme_cement).name}, batch A1"

    patch stock_count_line_path(count, line), params: { stock_count_line: { counted_quantity: "99" } }, as: :turbo_stream
    assert_match "batch by batch", response.body
    post stock_count_line_batch_counts_path(count, line), params: { number: "A1", counted_quantity: "4" }, as: :turbo_stream
    assert_select "turbo-stream[target=?]", dom_id(line)
    post stock_count_scan_path(count), params: { code: "CEM-50", batch_number: "z7", counted_quantity: "2" }
    assert_equal "#{products(:acme_cement).name}, batch Z7: 2 bag counted.", flash[:notice]
    expected = Account.without_isolation { line.reload.expected_quantity }
    assert_equal expected - 1 + 2, Account.without_isolation { line.counted_quantity }
  end

  test "scanning something not in the count" do
    post stock_counts_path, params: { stock_count: { branch_id: branches(:acme_main).id, category_id: categories(:acme_fasteners).id } }
    count = Account.without_isolation { StockCount.last }

    post stock_count_scan_path(count), params: { code: "CEM-50", counted_quantity: "3" }
    follow_redirect!
    assert_select "#alert", /isn't in this stock take/
  end
end
