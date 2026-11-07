require "test_helper"

class Pos::AirtelControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
    @merchant = Account.without_isolation do
      Current.set(account: accounts(:acme)) { accounts(:acme).airtel_merchants.create!(name: "Airtel Money", merchant_number: "5512345", environment: "simulator") }
    end
    post pos_lines_path, params: { code: "NAIL-3", quantity: "4" }, as: :turbo_stream
  end

  def current_sale
    Account.without_isolation { shifts(:acme_front_open).sales.order(:id).last }
  end

  test "a prompt goes to the customer's Airtel phone and the sale completes when they pay" do
    get pos_path
    assert_select "[data-payment-target=airtelFields] input[name=phone]"
    assert_select "input[value=airtel_money]"

    post pos_airtel_requests_path, params: { phone: "0733 000 111" }, as: :turbo_stream
    assert_match "Prompt sent to 0733 000 111", response.body
    request = Account.without_isolation { Airtel::Request.last }

    get pos_path
    assert_select "[data-controller=mpesa-poll]", /0733 000 111/

    get pos_airtel_request_path(request, format: :json)
    assert_equal "pending", response.parsed_body["status"]

    perform_enqueued_jobs(only: Airtel::SimulatedCallbackJob)
    get pos_airtel_request_path(request, format: :json)
    assert_equal "paid", response.parsed_body["status"]
    assert_equal pos_path(completed: request.sale_id), response.parsed_body["location"]
    sale = Account.without_isolation { request.sale.reload }
    assert sale.completed?
    assert_equal "airtel_money", Account.without_isolation { sale.payments.sole.tender }
  end

  test "a declined prompt tells the cashier, and they can stop waiting" do
    post pos_airtel_requests_path, params: { phone: "0733 110 000" }, as: :turbo_stream
    request = Account.without_isolation { Airtel::Request.last }
    perform_enqueued_jobs(only: Airtel::SimulatedCallbackJob)

    get pos_airtel_request_path(request, format: :json)
    assert_equal "failed", response.parsed_body["status"]
    get pos_path
    assert_match "Airtel Money not paid: Transaction declined by the customer", response.body

    post pos_airtel_requests_path, params: { phone: "0733 000 111" }, as: :turbo_stream
    delete pos_airtel_request_path(Account.without_isolation { Airtel::Request.last })
    assert Account.without_isolation { Airtel::Request.last.cancelled? }
  end

  test "a payment that arrived after the till stopped waiting is used on the sale" do
    post pos_airtel_requests_path, params: { phone: "0733 000 111" }, as: :turbo_stream
    request = Account.without_isolation { Airtel::Request.last }
    delete pos_airtel_request_path(request)
    Account.without_isolation do
      Current.set(account: accounts(:acme)) { @merchant.receive_callback(Airtel::SimulatedCallbackJob.payload(request.transaction_id, "733000111")) }
    end
    assert Account.without_isolation { request.reload.paid? }

    get pos_path
    assert_select "button", "Use"
    post pos_airtel_matches_path, params: { request_id: request.id }
    assert_redirected_to pos_path(completed: current_sale.id)
  end

  test "typing the transaction ID records Airtel Money without a prompt" do
    post pos_payments_path, params: { tender: "airtel_money" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match "Airtel Money transaction ID", response.body

    post pos_payments_path, params: { tender: "airtel_money", reference: "MP261107.1200.B55555" }, as: :turbo_stream
    assert_equal [ "airtel_money", "MP261107.1200.B55555" ], Account.without_isolation { current_sale.payments.sole.then { [ _1.tender, _1.reference ] } }
  end

  test "the Airtel tender is hidden while no merchant is set up" do
    Account.without_isolation { @merchant.update!(active: false) }
    get pos_path
    assert_select "[data-payment-target=airtelFields]", count: 0
  end

  test "owners connect Airtel Money; cashiers can't" do
    get airtel_merchants_path
    assert_response :forbidden

    sign_in_as users(:amina)
    get new_airtel_merchant_path
    assert_response :success
    post airtel_merchants_path, params: { airtel_merchant: { name: "Yard Airtel", environment: "simulator", merchant_number: "551 0001",
      branch_id: branches(:acme_yard).id } }
    assert_redirected_to airtel_merchants_path
    merchant = Account.without_isolation { Airtel::Merchant.find_by!(name: "Yard Airtel") }
    assert_equal "5510001", merchant.merchant_number

    get airtel_merchants_path
    assert_match merchant.callback_url, response.body

    post airtel_merchant_connection_test_path(merchant)
    assert_equal "Connected to Airtel with Yard Airtel's credentials.", flash[:notice]

    patch airtel_merchant_path(merchant), params: { airtel_merchant: { name: "Yard Airtel", client_secret: "", active: "0" } }
    assert_redirected_to airtel_merchants_path
    assert_not Account.without_isolation { merchant.reload.active? }
  end
end
