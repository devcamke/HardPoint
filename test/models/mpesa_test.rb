require "test_helper"

class MpesaTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shortcode = accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "sandbox",
      consumer_key: "key", consumer_secret: "secret", passkey: "passkey")
    @daraja = fake_transport(Mpesa::Client,
      "/oauth/v1/generate" => { access_token: "token-123" },
      "/mpesa/stkpush/v1/processrequest" => { MerchantRequestID: "m-1", CheckoutRequestID: "ws_CO_1", ResponseCode: "0" },
      "/mpesa/stkpushquery/v1/query" => { ResponseCode: "0", ResultCode: "1032", ResultDesc: "Request cancelled by user" },
      "/mpesa/c2b/v2/registerurl" => { ResponseCode: "0", ResponseDescription: "Success" })
    @sale = shifts(:acme_front_open).current_sale
    @sale.add(products(:acme_nails), quantity: 4) # 1,000.00
  end

  def paid_callback(checkout_request_id: "ws_CO_1", receipt: "SJK4H7T2QP", amount: 1000)
    { "Body" => { "stkCallback" => { "CheckoutRequestID" => checkout_request_id, "ResultCode" => 0, "ResultDesc" => "Processed", "CallbackMetadata" => { "Item" => [
      { "Name" => "Amount", "Value" => amount }, { "Name" => "MpesaReceiptNumber", "Value" => receipt },
      { "Name" => "TransactionDate", "Value" => 20260924101500 }, { "Name" => "PhoneNumber", "Value" => 254722000111 } ] } } } }
  end

  def c2b(trans_id: "SJQ82KD91L", amount: "500.00", bill_reference: "")
    { "TransactionType" => "Pay Bill", "TransID" => trans_id, "TransTime" => "20260924101500", "TransAmount" => amount,
      "BusinessShortCode" => "174379", "BillRefNumber" => bill_reference, "MSISDN" => "254722000111", "FirstName" => "JOHN" }
  end

  test "credentials are stored encrypted and each shortcode gets its own callback token" do
    raw = ActiveRecord::Base.connection.select_one("SELECT consumer_secret, passkey FROM mpesa_shortcodes WHERE id = #{@shortcode.id}")
    assert_not_includes raw.values.join, "secret"
    assert_equal "secret", @shortcode.reload.consumer_secret
    assert_equal 36, @shortcode.callback_token.length
  end

  test "a prompt to pay is sent with Daraja's password, whole shillings and the callback URL" do
    request = @shortcode.request_payment(sale: @sale, phone: "0722 000 111", amount_cents: 99_950)

    assert request.pending?
    assert_equal "ws_CO_1", request.checkout_request_id
    push = @daraja.last("/mpesa/stkpush/v1/processrequest")
    assert_equal "Bearer token-123", push.headers["Authorization"]
    assert_equal 1000, push.json[:Amount], "rounded up to whole shillings"
    assert_equal "254722000111", push.json[:PhoneNumber]
    assert_equal "CustomerPayBillOnline", push.json[:TransactionType]
    assert_equal Base64.strict_encode64("174379passkey#{push.json[:Timestamp]}"), push.json[:Password]
    assert_equal @shortcode.callback_url(:stk), push.json[:CallBackURL]
  end

  test "a paid prompt pays and completes the sale, once, however many callbacks come" do
    request = @shortcode.request_payment(sale: @sale, phone: "0722000111", amount_cents: @sale.balance_due_cents)

    2.times { @shortcode.receive_stk_callback(paid_callback) }

    assert request.reload.paid?
    assert @sale.reload.completed?
    assert_equal [ "SJK4H7T2QP" ], @sale.payments.map(&:reference)
    transaction = accounts(:acme).mpesa_transactions.sole
    assert_equal @sale.payments.sole, transaction.matched
    assert_equal "stk", transaction.source
  end

  test "a cancelled prompt leaves the sale open; money paid after the till stopped waiting is kept for matching" do
    request = @shortcode.request_payment(sale: @sale, phone: "0722000111", amount_cents: @sale.balance_due_cents)
    request.cancel

    @shortcode.receive_stk_callback(paid_callback)

    assert request.reload.cancelled?
    assert @sale.reload.open?
    assert_nil accounts(:acme).mpesa_transactions.sole.matched
  end

  test "a late callback is chased with a status check" do
    request = @shortcode.request_payment(sale: @sale, phone: "0722000111", amount_cents: @sale.balance_due_cents)
    request.update_columns(created_at: 1.minute.ago)

    request.check_status

    assert request.reload.cancelled?
    assert_equal "ws_CO_1", @daraja.last("/mpesa/stkpushquery/v1/query").json[:CheckoutRequestID]
  end

  test "Safaricom refusing the prompt is shown, not raised" do
    fake_transport(Mpesa::Client, "/oauth/v1/generate" => [ 400, { errorMessage: "Invalid Access Token" } ])

    request = @shortcode.request_payment(sale: @sale, phone: "0722000111", amount_cents: 100_00)
    assert request.failed?
    assert_match "consumer key", request.result_description
  end

  test "payments straight to the Paybill are recorded once and matched by the account number entered" do
    order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
      lines_attributes: [ { account: accounts(:acme), product_code: "NAIL-3", quantity: 10 } ])

    deposit = @shortcode.receive_c2b_confirmation(c2b(trans_id: "AAA1", bill_reference: order.reference.downcase))
    on_account = @shortcode.receive_c2b_confirmation(c2b(trans_id: "BBB2", bill_reference: "0722 000 111"))
    unknown = @shortcode.receive_c2b_confirmation(c2b(trans_id: "CCC3", bill_reference: "shop"))
    @shortcode.receive_c2b_confirmation(c2b(trans_id: "CCC3", bill_reference: "shop"))

    assert_equal 500_00, order.reload.deposit_balance_cents
    assert_equal deposit.reload.matched, order.deposits.sole
    assert_equal customers(:acme_contractor), on_account.reload.matched.customer
    assert_nil unknown.reload.matched
    assert_equal 3, accounts(:acme).mpesa_transactions.count
  end

  test "an unmatched payment can be used at the till, and a typed code claims one that already arrived" do
    received = @shortcode.receive_c2b_confirmation(c2b(trans_id: "DDD4", amount: "400.00"))
    received.attach_to(@sale)
    assert_equal 600_00, @sale.reload.balance_due_cents
    assert_raises(ArgumentError) { received.reload.attach_to(@sale) }

    arrived = @shortcode.receive_c2b_confirmation(c2b(trans_id: "EEE5", amount: "600.00"))
    @sale.pay(tender: "mobile_money", reference: "eee5")
    assert_equal @sale.payments.last, arrived.reload.matched

    # And the other way round: a code typed first is matched when Safaricom's record arrives.
    sale = shifts(:acme_front_open).current_sale
    sale.add(products(:acme_nails))
    payment = sale.pay(tender: "mobile_money", reference: "FFF6")
    assert_equal payment, @shortcode.receive_c2b_confirmation(c2b(trans_id: "FFF6", amount: "250.00")).matched
  end

  test "registering for payments made straight to the number" do
    @shortcode.register_c2b_urls

    registration = @daraja.last("/mpesa/c2b/v2/registerurl")
    assert_equal @shortcode.callback_url(:confirmation), registration.json[:ConfirmationURL]
    assert @shortcode.reload.c2b_registered_at
  end

  test "reconciliation shows money not used and codes Safaricom never confirmed" do
    @shortcode.receive_c2b_confirmation(c2b(trans_id: "GGG7", amount: "300.00"))
    @sale.pay(tender: "mobile_money", reference: "NOTREAL123")

    Time.use_zone(accounts(:acme).time_zone) do
      summary, received, unconfirmed = Report::MobileMoney.new(account: accounts(:acme), period: Report::Period.for_preset("today")).sections
      assert_equal [ "Received but not used", 1, 300_00 ], summary.rows[4]
      assert_equal "GGG7", received.rows.sole[1]
      assert_equal "NOTREAL123", unconfirmed.rows.sole[3]
    end
  end

  test "phone numbers in any usual form" do
    assert_equal "254722000111", PhoneNumber.normalize("0722 000 111")
    assert_equal "254722000111", PhoneNumber.normalize("+254 722 000 111")
    assert_equal "254110000111", PhoneNumber.normalize("0110000111")
    assert_nil PhoneNumber.normalize("12345")
    assert_equal "0722 000 111", PhoneNumber.display("254722000111")
  end
end
