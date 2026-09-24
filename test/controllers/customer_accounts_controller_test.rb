require "test_helper"

class CustomerAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation { memberships(:amina_acme).set_approval_pin("2468") }
    sign_in_as users(:carl) # cashier
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  def without_isolation(&) = Account.without_isolation(&)

  def create_quote(customer: customers(:acme_contractor), lines: { "0" => { product_code: "CEM-50", quantity: "10" }, "1" => { product_code: "", quantity: "" } })
    post customer_orders_path, params: { customer_order: { customer_id: customer.id, branch_id: branches(:acme_main).id, lines_attributes: lines } }
    without_isolation { CustomerOrder.last }
  end

  def current_sale
    without_isolation { shifts(:acme_front_open).sales.find_by!(status: "open") }
  end

  test "quote, email it, take a cash deposit, collect at the till using the deposit" do
    order = create_quote
    assert_redirected_to customer_order_path(order)
    assert without_isolation { order.quote? }
    assert_equal 760_000, order.total_cents

    get customer_order_path(order, format: :pdf)
    assert response.body.start_with?("%PDF")

    perform_enqueued_jobs { post customer_order_email_path(order) }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "accounts@mwangi.test" ], mail.to
    assert_equal "MAIN-O00001.pdf", mail.attachments.sole.filename

    post customer_order_deposits_path(order), params: { deposit: { amount: "2000", tender: "cash" } }
    assert_redirected_to customer_order_path(order)
    assert without_isolation { order.reload.ordered? }
    assert_equal 5_000_00 + 2_000_00, without_isolation { shifts(:acme_front_open).expected_cash_cents_now }

    post customer_order_collection_path(order)
    assert_redirected_to pos_path
    get pos_path
    assert_select "label", "Deposit"

    post pos_payments_path, params: { tender: "deposit" }, as: :turbo_stream
    post pos_payments_path, params: { tender: "card", reference: "VISA 1" }, as: :turbo_stream
    assert without_isolation { order.reload.collected? }
    assert_equal [ "deposit", "card" ], without_isolation { order.sales.sole.payments.map(&:tender) }
  end

  test "a cashier needs a manager's PIN to go over a customer's credit limit" do
    post pos_lines_path, params: { code: "CEM-50", quantity: "70" }, as: :turbo_stream # 70 × 760.00 = 53,200.00 > 50,000.00
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream

    post pos_payments_path, params: { tender: "on_account" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "approval PIN", response.body
    assert_select "input[name=tender][value=on_account][checked]", 1, "the account tender stays chosen"

    post pos_payments_path, params: { tender: "on_account", approval_pin: "0000" }, as: :turbo_stream
    assert_response :unprocessable_entity

    sale = current_sale
    post pos_payments_path, params: { tender: "on_account", approval_pin: "2468" }, as: :turbo_stream
    assert_equal users(:amina), without_isolation { sale.reload.credit_approver }
    assert without_isolation { sale.completed? }
  end

  test "payments on account, statements and who owes us" do
    sign_in_as users(:amina)
    customer = customers(:acme_contractor)
    without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale
        sale.change_customer(customer)
        sale.add(products(:acme_nails), quantity: 40)
        sale.pay(tender: "on_account")
      end
    end

    get receivables_path
    assert_select "td", /Mwangi Builders/

    post customer_payments_path(customer), params: { customer_payment: { amount: "4000", payment_method: "mobile_money", reference: "SJK4H7T2QP", paid_on: Date.current } }
    assert_redirected_to customer_path(customer)
    assert_equal 6_000_00, without_isolation { customer.balance_cents }

    get customer_statement_path(customer)
    assert_select "td", "Balance due"
    get customer_statement_path(customer, format: :pdf)
    assert response.body.start_with?("%PDF")

    perform_enqueued_jobs { post customer_statement_email_path(customer) }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "accounts@mwangi.test" ], mail.to
    assert_match "statement", mail.attachments.sole.filename
  end

  test "cashiers take account payments but don't see statements or who owes us" do
    get receivables_path
    assert_response :forbidden
    get customer_statement_path(customers(:acme_contractor))
    assert_response :forbidden

    get new_customer_payment_path(customers(:acme_contractor))
    assert_response :success
  end

  test "accountants see who owes us and customers, not orders or the till" do
    accountant = User.create!(name: "Alice Accounts", email_address: "alice@acme.test", password: "password")
    without_isolation { accounts(:acme).memberships.create!(user: accountant, role: :accountant) }
    sign_in_as accountant

    get receivables_path
    assert_response :success
    get customer_path(customers(:acme_contractor))
    assert_response :success
    get customer_orders_path
    assert_response :forbidden
  end

  test "delivery notes: create from a sale, dispatch, deliver with a photo, print" do
    post pos_lines_path, params: { code: "NAIL-3", quantity: "4" }, as: :turbo_stream
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    sale = current_sale
    post pos_payments_path, params: { tender: "on_account" }, as: :turbo_stream

    get new_delivery_note_path(sale_id: sale.id)
    assert_response :success
    post delivery_notes_path, params: { delivery_note: { sale_id: sale.id, address: "Plot 12, Mombasa Road", contact_phone: "0722000111" } }
    note = without_isolation { DeliveryNote.last }
    assert_redirected_to delivery_note_path(note)

    post delivery_note_dispatch_path(note), params: { driver_name: "Joseph", vehicle: "KDA 123B" }
    post delivery_note_delivery_path(note), params: { received_by: "Peter", proof_photo: fixture_file_upload("signed-note.png", "image/png") }
    assert without_isolation { note.reload.delivered? && note.proof_photo.attached? }

    get delivery_note_path(note)
    assert_select "img[alt='Signed delivery note']"
    get delivery_note_path(note, format: :pdf)
    assert response.body.start_with?("%PDF")
    get sale_invoice_path(sale)
    assert response.body.start_with?("%PDF")
  end

  test "another shop's orders and deliveries aren't found" do
    order = create_quote
    sign_in_as users(:bob)

    get customer_order_path(order)
    assert_response :not_found
  end
end
