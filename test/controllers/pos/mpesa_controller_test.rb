require "test_helper"

class Pos::MpesaControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
    @shortcode = Account.without_isolation do
      Current.set(account: accounts(:acme)) { accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator") }
    end
    post pos_lines_path, params: { code: "NAIL-3", quantity: "4" }, as: :turbo_stream
  end

  def current_sale
    Account.without_isolation { shifts(:acme_front_open).sales.order(:id).last }
  end

  test "a prompt goes to the customer's phone and the sale completes when they pay" do
    get pos_path
    assert_select "[data-payment-target=mpesaFields] input[name=phone]"

    post pos_mpesa_requests_path, params: { phone: "0722 000 111" }, as: :turbo_stream
    assert_match "Prompt sent to 0722 000 111", response.body
    request = Account.without_isolation { Mpesa::StkRequest.last }

    get pos_path
    assert_select "[data-controller=mpesa-poll]", /Waiting for 0722 000 111/

    get pos_mpesa_request_path(request, format: :json)
    assert_equal "pending", response.parsed_body["status"]

    perform_enqueued_jobs(only: Mpesa::SimulatedCallbackJob)
    get pos_mpesa_request_path(request, format: :json)
    assert_equal "paid", response.parsed_body["status"]
    assert_equal pos_path(completed: request.sale_id), response.parsed_body["location"]
    assert Account.without_isolation { request.sale.reload.completed? }
  end

  test "a declined prompt tells the cashier, and they can stop waiting" do
    post pos_mpesa_requests_path, params: { phone: "0711 110 000" }, as: :turbo_stream
    request = Account.without_isolation { Mpesa::StkRequest.last }
    perform_enqueued_jobs(only: Mpesa::SimulatedCallbackJob)

    get pos_mpesa_request_path(request, format: :json)
    assert_equal "cancelled", response.parsed_body["status"]
    follow_redirect! rescue nil
    get pos_path
    assert_match "M-Pesa not paid: Request cancelled by user", response.body

    post pos_mpesa_requests_path, params: { phone: "0722 000 111" }, as: :turbo_stream
    delete pos_mpesa_request_path(Account.without_isolation { Mpesa::StkRequest.last })
    assert Account.without_isolation { Mpesa::StkRequest.last.cancelled? }
  end

  test "money that arrived on the Paybill is used on the sale" do
    transaction = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        @shortcode.receive_c2b_confirmation("TransID" => "SJQ82KD91L", "TransAmount" => "1000.00", "TransTime" => Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S"), "MSISDN" => "254722000111")
      end
    end
    get pos_path
    assert_select "button", "Use"

    post pos_mpesa_matches_path, params: { transaction_id: transaction.id }
    assert_redirected_to pos_path(completed: current_sale.id)
  end

  test "owners connect a Paybill; cashiers can't" do
    get mpesa_shortcodes_path
    assert_response :forbidden

    sign_in_as users(:amina)
    post mpesa_shortcodes_path, params: { mpesa_shortcode: { name: "Yard till", transaction_type: "buy_goods", environment: "simulator",
      shortcode: "600100", till_number: "5123456", branch_id: branches(:acme_yard).id } }
    assert_redirected_to mpesa_shortcodes_path
    post mpesa_shortcode_connection_test_path(Account.without_isolation { Mpesa::Shortcode.find_by!(shortcode: "600100") })
    assert_equal "Connected to Safaricom: Till 5123456 is ready.", flash[:notice]
  end

  test "a cashier bound to a branch uses only payments to its own Till or the shop-wide one, and prompts sent from this till" do
    Account.without_isolation { memberships(:carl_acme).update!(branch: branches(:acme_main)) }
    now = Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S")
    yard_till, shop_wide, other_till_prompt = Account.without_isolation do
      Current.set(account: accounts(:acme), session: accounts(:acme).sessions.create!(user: users(:carl))) do
        yard = accounts(:acme).mpesa_shortcodes.create!(name: "Yard till", shortcode: "600100", transaction_type: "buy_goods", till_number: "5123456",
          environment: "simulator", branch: branches(:acme_yard))
        yard_shift = accounts(:acme).shifts.create!(branch: branches(:acme_yard), register: registers(:acme_yard), opened_by: users(:carl), opening_float_cents: 0, opened_at: Time.current)
        yard_sale = yard_shift.current_sale.tap { _1.add(products(:acme_cement)) }
        prompt = @shortcode.stk_requests.create!(account: accounts(:acme), sale: yard_sale, phone: "254722000333", amount_cents: 700_00, checkout_request_id: "ws_CO_YARD1")
        prompt.update!(status: :expired)
        late = { "Body" => { "stkCallback" => { "CheckoutRequestID" => "ws_CO_YARD1", "ResultCode" => 0, "ResultDesc" => "OK",
          "CallbackMetadata" => { "Item" => [ { "Name" => "MpesaReceiptNumber", "Value" => "SJQYARD001" }, { "Name" => "Amount", "Value" => 700 } ] } } } }
        @shortcode.receive_stk_callback(late)
        [ yard.receive_c2b_confirmation("TransID" => "SJQYARD002", "TransAmount" => "1000.00", "TransTime" => now, "MSISDN" => "254722000222", "FirstName" => "Yardpayer"),
          @shortcode.receive_c2b_confirmation("TransID" => "SJQSHOP003", "TransAmount" => "1000.00", "TransTime" => now, "MSISDN" => "254722000111"),
          accounts(:acme).mpesa_transactions.find_by!(trans_id: "SJQYARD001") ]
      end
    end

    get pos_path
    assert_select ".font-mono", text: "SJQSHOP003"
    assert_select ".font-mono", text: "SJQYARD002", count: 0
    assert_select ".font-mono", text: "SJQYARD001", count: 0

    post pos_mpesa_matches_path, params: { transaction_id: yard_till.id }
    assert_response :not_found
    post pos_mpesa_matches_path, params: { transaction_id: other_till_prompt.id }
    assert_response :not_found
    post pos_mpesa_matches_path, params: { transaction_id: shop_wide.id }
    assert_redirected_to pos_path(completed: current_sale.id)
  end
end
