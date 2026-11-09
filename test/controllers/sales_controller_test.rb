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

  test "the number on an offline receipt finds the sale" do
    Account.without_isolation { @sale.update_columns(offline_uuid: SecureRandom.uuid, offline_receipt_number: "MAIN-OFF1-K7Q2-0001") }

    get sales_path(query: "main-off1-k7q2-0001")
    assert_select "td a", "MAIN-000001"

    get sales_path(query: "MAIN-OFF1-K7Q2-0002")
    assert_select "tbody tr", 0
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
    assert_equal "cash", @sale.void_refund_method, "a cash sale is refunded in cash unless told otherwise"
    assert_equal 50, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_main)) }

    follow_redirect!
    assert_select "p", /KES 1,600.00 refunded in cash/
  end

  test "voiding a sale paid by phone asks for the reversal's code, and Activity records how the money went back" do
    paid_by_phone = Current.set(account: accounts(:acme), session: Account.without_isolation { accounts(:acme).sessions.create!(user: users(:carl)) }) do
      shifts(:acme_front_open).current_sale.tap { |sale| sale.add(products(:acme_pipe)); sale.pay(tender: "mobile_money", reference: "SJK4H7T2QP") }
    end

    get new_sale_void_path(paid_by_phone)
    assert_select "input[name=refund_method][value=mobile_money][checked]"

    post sale_void_path(paid_by_phone), params: { reason: "Wrong customer", approval_pin: "2468", refund_method: "mobile_money" }
    assert_response :unprocessable_entity
    assert_select "#alert", /M-Pesa reversal code/

    post sale_void_path(paid_by_phone), params: { reason: "Wrong customer", approval_pin: "2468", refund_method: "mobile_money", refund_reference: "SJK4H7T2QR" }
    assert_redirected_to sale_path(paid_by_phone)
    assert_equal [ "mobile_money", "SJK4H7T2QR" ], Account.without_isolation { paid_by_phone.reload.values_at(:void_refund_method, :void_refund_reference) }

    sign_in_as users(:amina)
    get events_path
    assert_select "li", /voided sale MAIN-000002 .*: Wrong customer; refunded by M-Pesa \(SJK4H7T2QR\)/
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

  test "cash movements go on this device's till only, and a big payout needs a manager's PIN" do
    yard = Account.without_isolation { accounts(:acme).shifts.create!(branch: branches(:acme_yard), register: registers(:acme_yard), opened_by: users(:carl), opening_float_cents: 100000) }
    get new_shift_cash_movement_path(yard)
    assert_response :not_found
    post shift_cash_movements_path(yard), params: { cash_movement: { kind: "drop", amount: "100", reason: "To safe" } }
    assert_response :not_found

    post shift_cash_movements_path(shifts(:acme_front_open)), params: { cash_movement: { kind: "payout", amount: "6000", reason: "Cement delivery" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation li", /payout over KES 5,000.00 needs a manager's approval PIN/
    assert_equal 0, Account.without_isolation { shifts(:acme_front_open).cash_movements.count }

    post shift_cash_movements_path(shifts(:acme_front_open)), params: { approval_pin: "2468", cash_movement: { kind: "payout", amount: "6000", reason: "Cement delivery" } }
    assert_redirected_to shift_path(shifts(:acme_front_open))
    event = Account.without_isolation { shifts(:acme_front_open).events.last }
    assert_equal [ "payout_approved", "Amina Owner", 600000 ], [ event.action, event.particulars["approver"], event.particulars["amount"] ]

    post shift_cash_movements_path(shifts(:acme_front_open)), params: { cash_movement: { kind: "payout", amount: "4000", reason: "Lunch" } }
    assert_redirected_to shift_path(shifts(:acme_front_open)), "under the limit, no PIN needed"
    assert_equal 500000 + 160000 - 600000 - 400000, Account.without_isolation { shifts(:acme_front_open).expected_cash_cents_now }
  end

  test "another shop's sales are out of reach" do
    sign_in_as users(:bob)
    get sale_path(@sale)
    assert_response :not_found
  end
end
