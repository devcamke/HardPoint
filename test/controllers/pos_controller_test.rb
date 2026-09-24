require "test_helper"

class PosControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:carl)
    use_till registers(:acme_front) unless name.include?("asks_for_one")
  end

  def use_till(register)
    post pos_till_path, params: { register_id: register.id }
  end

  def current_sale
    Account.without_isolation { shifts(:acme_front_open).sales.find_by!(status: "open") }
  end

  test "a device picks its till once" do
    get pos_path
    assert_response :success
    assert_select "header", /Front counter/
  end

  test "without a till or an open shift the till asks for one" do
    get pos_path
    assert_redirected_to new_pos_till_path

    use_till registers(:acme_yard)
    get pos_path
    assert_redirected_to new_shift_path

    post shifts_path, params: { shift: { opening_float: "3000" } }
    assert_redirected_to pos_path
  end

  test "scanning barcodes, SKUs and pack barcodes" do
    post pos_lines_path, params: { code: "6161100420017" }, as: :turbo_stream
    post pos_lines_path, params: { code: "6161100420017" }, as: :turbo_stream
    post pos_lines_path, params: { code: "6001234500012" }, as: :turbo_stream
    post pos_lines_path, params: { code: "nail-3" }, as: :turbo_stream
    assert_response :success
    assert_match "Wire nails", response.body

    lines = Account.without_isolation { current_sale.lines.map { [ _1.product.sku, _1.quantity.to_i, _1.product_unit_id.present? ] } }
    assert_equal [ [ "CEM-50", 2, false ], [ "SCR-815", 1, true ], [ "NAIL-3", 1, false ] ], lines
  end

  test "an unknown code says so" do
    post pos_lines_path, params: { code: "0000000000000" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "Nothing found", response.body
  end

  test "another shop's barcode isn't found" do
    post pos_lines_path, params: { code: "0076174512345" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "changing quantity and pack reprices the line" do
    post pos_lines_path, params: { code: "SCR-815" }, as: :turbo_stream
    line = Account.without_isolation { current_sale.lines.sole }

    patch pos_line_path(line), params: { sale_line: { quantity: "3", product_unit_id: product_units(:acme_screws_box).id } }, as: :turbo_stream
    assert_equal 120000, Account.without_isolation { current_sale.total_cents }
  end

  test "big discounts need a manager's approval PIN" do
    Account.without_isolation { memberships(:amina_acme).set_approval_pin("2468") }
    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    line = Account.without_isolation { current_sale.lines.sole }

    patch pos_line_path(line), params: { sale_line: { discount: "200" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "needs a manager", response.body
    assert_equal 80000, Account.without_isolation { current_sale.total_cents }, "the discount was rolled back"

    patch pos_line_path(line), params: { sale_line: { discount: "200" }, approval_pin: "2468" }, as: :turbo_stream
    assert_response :success
    assert_equal 60000, Account.without_isolation { current_sale.total_cents }
    assert_equal users(:amina), Account.without_isolation { current_sale.discount_approver }

    patch pos_discount_path, params: { discount: "5%" }, as: :turbo_stream
    assert_response :success, "within the cashier's own limit"
  end

  test "choosing a contractor switches to their prices" do
    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream

    assert_equal 76000, Account.without_isolation { current_sale.total_cents }
  end

  test "another shop's customer can't be chosen" do
    patch pos_customer_path, params: { customer_id: customers(:bolt_customer).id }, as: :turbo_stream
    assert_response :not_found
  end

  test "split payment completes the sale and shows the change" do
    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    post pos_lines_path, params: { code: "PVC-2" }, as: :turbo_stream

    post pos_payments_path, params: { tender: "mobile_money", amount: "1000", reference: "SJK4H7T2QP" }, as: :turbo_stream
    assert_response :success
    assert_match "still due", response.body

    post pos_payments_path, params: { tender: "cash", tendered: "1500" }, as: :turbo_stream
    sale = Account.without_isolation { Sale.completed.last }
    assert_redirected_to pos_path(completed: sale.id)

    assert_equal users(:carl), sale.cashier
    follow_redirect!
    assert_select "p", /Change KES 500.00/
    assert_select "p", /MAIN-000001/
  end

  test "park, serve someone else, recall" do
    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    parked = current_sale
    post pos_parking_path
    assert_redirected_to pos_path

    post pos_lines_path, params: { code: "PVC-2" }, as: :turbo_stream
    post sale_recall_path(parked)
    assert_redirected_to pos_parked_sales_path, "the till is busy with another sale"

    post pos_discard_path
    post sale_recall_path(parked)
    assert_redirected_to pos_path
    assert_equal parked, current_sale
  end

  test "accountants can't sell" do
    Account.without_isolation { memberships(:carl_acme).update!(role: :accountant) }
    get pos_path
    assert_response :forbidden
  end
end
