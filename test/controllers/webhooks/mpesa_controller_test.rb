require "test_helper"

class Webhooks::MpesaControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        @shortcode = accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator")
        @sale = shifts(:acme_front_open).current_sale
        @sale.add(products(:acme_nails), quantity: 4)
        @stk_request = @sale.stk_requests.create!(account: accounts(:acme), shortcode: @shortcode, phone: "254722000111", amount_cents: 1000_00,
          checkout_request_id: "ws_CO_42")
      end
    end
    use_apex_domain
  end

  def paid(checkout_request_id = "ws_CO_42")
    { Body: { stkCallback: { CheckoutRequestID: checkout_request_id, ResultCode: 0, ResultDesc: "OK", CallbackMetadata: { Item: [
      { Name: "Amount", Value: 1000 }, { Name: "MpesaReceiptNumber", Value: "SJK4H7T2QP" }, { Name: "PhoneNumber", Value: 254722000111 } ] } } } }
  end

  test "a paid callback pays the sale, and Safaricom always gets ResultCode 0" do
    post mpesa_webhook_stk_path(@shortcode.callback_token), params: paid.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :success
    assert_equal({ "ResultCode" => 0, "ResultDesc" => "Accepted" }, response.parsed_body)
    assert Account.without_isolation { @sale.reload.completed? }

    post mpesa_webhook_stk_path(@shortcode.callback_token), params: "not json", headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  test "payments straight to the Paybill are recorded, and validation accepts them" do
    post mpesa_webhook_validation_path(@shortcode.callback_token), params: { TransID: "X1" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_equal 0, response.parsed_body["ResultCode"]

    post mpesa_webhook_confirmation_path(@shortcode.callback_token),
      params: { TransID: "SJQ82KD91L", TransAmount: "250.00", TransTime: "20260924101500", BillRefNumber: "", MSISDN: "254722000111" }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_equal 250_00, Account.without_isolation { Mpesa::Transaction.find_by!(trans_id: "SJQ82KD91L").amount_cents }
  end

  test "the shop comes from the token, never the payload" do
    post mpesa_webhook_stk_path("not-a-token"), params: paid.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :not_found

    # Another shop's valid token can't settle this shop's prompt, even naming its checkout ID.
    bolt = Account.without_isolation do
      Current.set(account: accounts(:bolt)) { accounts(:bolt).mpesa_shortcodes.create!(name: "Bolt", shortcode: "600000", environment: "simulator") }
    end
    post mpesa_webhook_stk_path(bolt.callback_token), params: paid.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :success
    assert Account.without_isolation { @stk_request.reload.pending? }
  end

  test "only Safaricom's addresses are accepted when they're configured" do
    Rails.configuration.x.mpesa_callback_ips = [ IPAddr.new("196.201.214.200") ]
    post mpesa_webhook_stk_path(@shortcode.callback_token), params: paid.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :forbidden

    post mpesa_webhook_stk_path(@shortcode.callback_token), params: paid.to_json,
      headers: { "Content-Type" => "application/json", "REMOTE_ADDR" => "196.201.214.200" }
    assert_response :success
  ensure
    Rails.configuration.x.mpesa_callback_ips = []
  end
end
