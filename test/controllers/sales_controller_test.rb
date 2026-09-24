require "test_helper"

class SalesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation { memberships(:amina_acme).set_approval_pin("2468") }
    @sale = Current.set(account: accounts(:acme), session: Account.without_isolation { accounts(:acme).sessions.create!(user: users(:carl)) }) do
      shifts(:acme_front_open).current_sale.tap do |sale|
        sale.add(products(:acme_cement), quantity: 2)
        sale.pay(tender: "cash", tendered_cents: 200000)
      end
    end
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  test "sales list and receipt" do
    get sales_path
    assert_select "td a", "MAIN-000001"

    get sales_path(branch_id: branches(:acme_yard).id)
    assert_select "tbody tr", 0

    get sales_path(branch_id: "")
    assert_select "tbody tr", 1, "all branches"

    get sales_path(query: "main-000001")
    assert_select "tbody tr", 1

    get sale_receipt_path(@sale)
    assert_response :success
    assert_select ".receipt", /TOTAL\s*KES 1,600.00/
    assert_select ".receipt", /Change\s*KES 400.00/
  end

  test "emailing the receipt" do
    perform_enqueued_jobs do
      post sale_receipt_email_path(@sale), params: { email: "grace@example.test" }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "grace@example.test" ], mail.to
    assert_match "MAIN-000001", mail.subject
  end

  test "voiding needs a reason and an approval PIN" do
    post sale_void_path(@sale), params: { reason: "Rang up twice" }
    assert_response :unprocessable_entity

    post sale_void_path(@sale), params: { reason: "Rang up twice", approval_pin: "2468" }
    assert_redirected_to sale_path(@sale)
    assert Account.without_isolation { @sale.reload.voided? }
    assert_equal 50, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_main)) }
  end

  test "returning one bag with approval" do
    line = Account.without_isolation { @sale.lines.sole }
    params = { sale_return: { refund_method: "cash", lines_attributes: { "0" => { sale_line_id: line.id, quantity: "1", restock: "1" } } } }

    post sale_returns_path(@sale), params: params
    assert_response :unprocessable_entity, "needs approval"

    post sale_returns_path(@sale), params: params.merge(approval_pin: "2468")
    sale_return = Account.without_isolation { SaleReturn.last }
    assert_redirected_to return_path(sale_return)
    assert_equal 80000, sale_return.total_cents
    assert_equal 49, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_main)) }
    assert_equal 500000 + 160000 - 80000, Account.without_isolation { shifts(:acme_front_open).expected_cash_cents_now }
  end

  test "can't return a line from another sale" do
    other = Current.set(account: accounts(:acme), session: Account.without_isolation { accounts(:acme).sessions.create!(user: users(:carl)) }) do
      shifts(:acme_front_open).current_sale.tap { |sale| sale.add(products(:acme_pipe)); sale.pay(tender: "card") }
    end
    foreign_line = Account.without_isolation { other.lines.sole }

    post sale_returns_path(@sale), params: { approval_pin: "2468", sale_return: { refund_method: "cash", lines_attributes: { "0" => { sale_line_id: foreign_line.id, quantity: "1" } } } }
    assert_response :unprocessable_entity
  end

  test "closing the shift with a blind count" do
    get new_shift_closing_path(shifts(:acme_front_open))
    assert_select "body", text: /Expected/, count: 0

    post shift_closing_path(shifts(:acme_front_open)), params: { counted_cash: "6590" }
    assert_redirected_to shift_path(shifts(:acme_front_open))

    follow_redirect!
    assert_select "div", /Short\s*-KES 10.00/
  end

  test "cash drops show in the X report" do
    post shift_cash_movements_path(shifts(:acme_front_open)), params: { cash_movement: { kind: "drop", amount: "1000", reason: "To safe" } }
    get shift_path(shifts(:acme_front_open))
    assert_select "div", /Expected in drawer\s*KES 5,600.00/
  end

  test "another shop's sales are out of reach" do
    sign_in_as users(:bob)
    get sale_path(@sale)
    assert_response :not_found
  end
end
