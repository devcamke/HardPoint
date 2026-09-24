# Paystack's webhooks, trusted only with a valid HMAC-SHA512 signature of the raw body. A
# successful charge pays its invoice once, however many times Paystack sends it.
class Webhooks::PaystackController < ActionController::API
  def create
    return head(:unauthorized) unless Billing::Paystack.valid_signature?(request.raw_post, request.headers["X-Paystack-Signature"])

    event = JSON.parse(request.raw_post)
    if event["event"] == "charge.success"
      data = event["data"] || {}
      payment = Account.without_isolation { Billing::Payment.find_by(provider: "paystack", reference: data["reference"].to_s) }
      if payment
        Current.set(account: payment.account) do
          payment.succeed(receipt: data["reference"], amount_cents: data["amount"].to_i) if data["currency"] == payment.invoice.currency
        end
      end
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
