# Card payments (and Paystack's own M-Pesa) through Paystack's hosted checkout. The secret key lives
# under billing: { paystack_secret_key: }; without it, development and demos use a simulated checkout.
class Billing::Paystack
  BASE_URL = "https://api.paystack.co"

  Refused = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  def self.secret_key
    Rails.configuration.x.paystack_secret_key.presence || Rails.application.credentials.dig(:billing, :paystack_secret_key)
  end

  def self.simulated?
    secret_key.blank?
  end

  def self.available?
    !simulated? || Mpesa::Shortcode.simulator_allowed?
  end

  # Paystack signs each webhook with an HMAC-SHA512 of the raw body, keyed with the secret key.
  def self.valid_signature?(body, signature)
    secret_key.present? && signature.present? &&
      ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA512", secret_key, body), signature)
  end

  # Starts a checkout and returns the page to send the owner to.
  def checkout_url(payment, email:, callback_url:)
    body = request(:post, "/transaction/initialize", json: { email: email, amount: payment.amount_cents, currency: payment.invoice.currency,
      reference: payment.reference, callback_url: callback_url, metadata: { invoice: payment.invoice.number, account_id: payment.account_id } })
    url = body.dig("data", "authorization_url").to_s
    raise Refused, "Paystack sent an unexpected checkout address" unless URI.parse(url).then { _1.is_a?(URI::HTTPS) && _1.host.to_s.end_with?(".paystack.com") }
    url
  rescue URI::InvalidURIError
    raise Refused, "Paystack sent an unexpected checkout address"
  end

  # What Paystack says happened to a checkout: [ status, amount in cents, currency ].
  def verify(reference)
    data = request(:get, "/transaction/verify/#{ERB::Util.url_encode(reference)}")["data"] || {}
    [ data["status"], data["amount"].to_i, data["currency"] ]
  end

  private
    def request(method, path, json: nil)
      response = transport.request(method, "#{BASE_URL}#{path}", headers: { "Authorization" => "Bearer #{self.class.secret_key}" }, json: json)
      raise JsonHttp::Unreachable, "Paystack answered #{response.status}" if response.status >= 500
      raise Refused, response.body["message"] || "Paystack said no (#{response.status})" unless response.success? && response.body["status"]

      response.body
    end
end
