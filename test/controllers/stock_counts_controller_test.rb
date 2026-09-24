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

  test "scanning something not in the count" do
    post stock_counts_path, params: { stock_count: { branch_id: branches(:acme_main).id, category_id: categories(:acme_fasteners).id } }
    count = Account.without_isolation { StockCount.last }

    post stock_count_scan_path(count), params: { code: "CEM-50", counted_quantity: "3" }
    follow_redirect!
    assert_select "#alert", /isn't in this stock take/
  end
end
