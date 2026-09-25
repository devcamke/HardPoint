require "test_helper"

class PromotionsControllerTest < ActionDispatch::IntegrationTest
  setup { @account = accounts(:acme) }

  def acme(&) = Account.without_isolation(&)

  test "a manager sets one up by SKU, the till applies it, and it shows everywhere" do
    sign_in_as users(:amina), account: @account
    post promotions_path, params: { promotion: { name: "Cement week", kind: "buy_get", buy_quantity: "10", free_quantity: "1", product_codes: "CEM-50 NOPE-9",
      starts_on: Date.current, ends_on: Date.current + 7 } }
    assert_response :unprocessable_entity
    assert_match "NOPE-9", response.body

    post promotions_path, params: { promotion: { name: "Cement week", kind: "buy_get", buy_quantity: "10", free_quantity: "1", product_codes: "CEM-50",
      starts_on: Date.current, ends_on: Date.current + 7, branch_ids: [ "" ], category_ids: [ "" ] } }
    promotion = acme { @account.promotions.last }
    assert_redirected_to promotion_path(promotion)

    post pos_till_path, params: { register_id: registers(:acme_front).id }
    post pos_lines_path, params: { code: "CEM-50", quantity: 11 }, as: :turbo_stream
    assert_match "Buy 10, get 1 free", response.body
    post pos_payments_path, params: { tender: "card", reference: "VISA 1" }
    sale = acme { @account.sales.completed.last }
    get sale_receipt_path(sale)
    assert_match "You saved", response.body

    get promotions_path
    assert_select "##{dom_id(promotion)}", /Cement week/
    get promotion_path(promotion)
    assert_select ".card", /800/
    get product_path(products(:acme_cement))
    assert_match "On promotion", response.body

    delete promotion_path(promotion)
    assert_not acme { promotion.reload.active? }, "used promotions end rather than disappear"
  end

  test "cashiers see promotions but can't change them" do
    sign_in_as users(:carl), account: @account
    get promotions_path
    assert_response :success
    get new_promotion_path
    assert_response :forbidden
  end
end
