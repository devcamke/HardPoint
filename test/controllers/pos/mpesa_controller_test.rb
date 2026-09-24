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
end
