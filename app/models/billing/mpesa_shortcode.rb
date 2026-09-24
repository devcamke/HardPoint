# HardPoint's own Paybill, which shops pay their subscription to. It stands in for an
# Mpesa::Shortcode, so the same Daraja client and simulator serve it. Credentials live under
# billing: { mpesa: { environment:, shortcode:, passkey:, consumer_key:, consumer_secret:, callback_token: } };
# without them, development and demos use the simulator.
class Billing::MpesaShortcode
  include GlobalID::Identification

  def self.find(_id) = new
  def id = "platform"

  def settings
    Rails.configuration.x.billing_mpesa.presence || Rails.application.credentials.dig(:billing, :mpesa) ||
      { environment: "simulator", shortcode: "174379", callback_token: "simulator" }
  end

  def available?
    settings[:environment] != "simulator" || Mpesa::Shortcode.simulator_allowed?
  end

  %i[ shortcode passkey consumer_key consumer_secret environment callback_token ].each do |name|
    define_method(name) { settings[name].to_s }
  end

  def simulator? = environment == "simulator"
  def buy_goods? = false
  def party_b = shortcode
  def daraja_transaction_type = "CustomerPayBillOnline"
  def label = "Paybill #{shortcode}"

  def client
    Mpesa::Client.new(self)
  end

  def callback_url(_kind = :stk)
    Rails.application.routes.url_helpers.billing_mpesa_webhook_url(callback_token, **Rails.configuration.x.webhook_url_options)
  end

  def request_payment(invoice:, phone:)
    payment = invoice.payments.create!(account: invoice.account, provider: "mpesa", amount_cents: invoice.amount_cents, phone: phone,
      reference: "pending-#{SecureRandom.uuid}")
    response = client.stk_push(phone: phone, amount: (invoice.amount_cents / 100.0).ceil, reference: invoice.number.delete("-"),
      description: "HardPoint", callback_url: callback_url)
    payment.update!(reference: response["CheckoutRequestID"])
    payment
  rescue Mpesa::Client::Refused, JsonHttp::Unreachable => error
    payment&.fail(error.message)
    payment
  end

  # Safaricom's answer to the prompt; the payment is found by its checkout ID across shops.
  def receive_stk_callback(payload)
    callback = payload.dig("Body", "stkCallback") or return
    payment = Account.without_isolation { Billing::Payment.pending.find_by(provider: "mpesa", reference: callback["CheckoutRequestID"].to_s) } or return
    details = Array(callback.dig("CallbackMetadata", "Item")).to_h { [ _1["Name"], _1["Value"] ] }

    Current.set(account: payment.account) do
      if callback["ResultCode"].to_s == "0"
        payment.succeed(receipt: details["MpesaReceiptNumber"], amount_cents: Monetary.to_cents(details["Amount"]))
      else
        payment.fail(callback["ResultDesc"])
      end
    end
  end
end
