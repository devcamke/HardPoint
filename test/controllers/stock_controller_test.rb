require "test_helper"

class StockControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "overview shows the stock value and that the books balance" do
    get stock_path

    assert_response :success
    # 60 bags of cement × 700, 25.5 kg nails × 180, 1000 screws × 3, 3 pipes × 900
    assert_select ".card", /KES 52,290.00/
    assert_select ".badge", "✓ Balanced"
  end

  test "adjusting stock" do
    post stock_adjustments_path, params: { stock_adjustment: { product_id: products(:acme_cement).id, branch_id: branches(:acme_main).id, reason: "damaged", quantity: "-2", note: "Rain" } }

    assert_redirected_to product_path(products(:acme_cement))
    assert_equal 48, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_main)) }
  end

  test "invalid adjustments explain why" do
    post stock_adjustments_path, params: { stock_adjustment: { product_id: products(:acme_cement).id, branch_id: branches(:acme_main).id, reason: "damaged", quantity: "5" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation", /must be negative/
  end

  test "another shop's branch or product can't be adjusted" do
    post stock_adjustments_path, params: { stock_adjustment: { product_id: products(:bolt_hammer).id, branch_id: branches(:acme_main).id, reason: "found", quantity: "1" } }
    assert_response :not_found
  end

  test "reorder list shows what's low at the branch" do
    get reorder_list_path(branch_id: branches(:acme_main).id)
    assert_select "td a", "PVC pipe 2 inch 6m"
    assert_select "td a", text: "Bamburi cement 50kg", count: 0

    get reorder_list_path(branch_id: branches(:acme_yard).id)
    assert_select "td a", "Bamburi cement 50kg"
  end

  test "movements list" do
    get stock_movements_path(all_branches: "1", reason: "opening")
    assert_response :success
    assert_select "tbody tr", 5
  end

  test "cashiers can't adjust stock" do
    sign_in_as users(:carl)
    get new_stock_adjustment_path(product_id: products(:acme_cement).id)
    assert_response :forbidden
  end
end
