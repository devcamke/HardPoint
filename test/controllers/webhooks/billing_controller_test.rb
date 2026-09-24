require "test_helper"

class Webhooks::BillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.paystack_secret_key = "sk_test_123"
    Rails.configuration.x.billing_mpesa = { environment: "simulator", shortcode: "600900", callback_token: "platform-token" }
    Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        @invoice = accounts(:acme).start_subscription_now
        @card = @invoice.payments.create!(account: accounts(:acme), provider: "paystack", amount_cents: @invoice.amount_cents, reference: "HP-CARD-1")
        @mpesa = @invoice.payments.create!(account: accounts(:acme), provider: "mpesa", amount_cents: @invoice.amount_cents, reference: "ws_CO_PLATFORM")
      end
    end
    use_apex_domain
  end

  teardown do
    Rails.configuration.x.paystack_secret_key = nil
    Rails.configuration.x.billing_mpesa = nil
  end

  def paystack(body, signature: OpenSSL::HMAC.hexdigest("SHA512", "sk_test_123", body))
    post paystack_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Paystack-Signature" => signature }
  end

  test "Paystack's signed charge.success pays the invoice once" do
    body = { event: "charge.success", data: { reference: "HP-CARD-1", amount: @invoice.amount_cents, currency: "KES" } }.to_json

    paystack body
    assert_response :success
    assert Account.without_isolation { @invoice.reload.paid? }

    paystack body
    assert_response :success
    assert_equal 1, Account.without_isolation { Billing::Payment.succeeded.count }
  end

  test "an unsigned or wrongly signed Paystack webhook is refused" do
    body = { event: "charge.success", data: { reference: "HP-CARD-1", amount: @invoice.amount_cents, currency: "KES" } }.to_json

    paystack body, signature: "forged"
    assert_response :unauthorized
    assert Account.without_isolation { @invoice.reload.open? }
  end

  test "Safaricom's answer to a subscription prompt pays the invoice" do
    callback = { Body: { stkCallback: { CheckoutRequestID: "ws_CO_PLATFORM", ResultCode: 0, CallbackMetadata: { Item: [
      { Name: "Amount", Value: @invoice.amount_cents / 100 }, { Name: "MpesaReceiptNumber", Value: "SKB7654321" } ] } } } }.to_json

    post billing_mpesa_webhook_path("wrong-token"), params: callback, headers: { "Content-Type" => "application/json" }
    assert_response :not_found

    post billing_mpesa_webhook_path("platform-token"), params: callback, headers: { "Content-Type" => "application/json" }
    assert_equal 0, response.parsed_body["ResultCode"]
    assert Account.without_isolation { @invoice.reload.paid? }
  end
end
