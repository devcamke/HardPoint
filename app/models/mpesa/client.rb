# The Daraja API for one shortcode. Each call gets a fresh OAuth token (they last an hour; an extra
# request per prompt is cheaper than keeping tokens anywhere).
class Mpesa::Client
  BASE_URLS = { "sandbox" => "https://sandbox.safaricom.co.ke", "production" => "https://api.safaricom.co.ke" }.freeze

  # Safaricom refused the request (bad credentials, wrong number…); retrying won't help.
  Refused = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  attr_reader :shortcode

  def initialize(shortcode)
    @shortcode = shortcode
  end

  def access_token
    response = http.request(:get, url("/oauth/v1/generate?grant_type=client_credentials"),
      headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{shortcode.consumer_key}:#{shortcode.consumer_secret}")}" })
    response.body["access_token"] or raise Refused, "Safaricom didn't accept the consumer key and secret (#{response.status})"
  end

  # Asks the customer's phone to approve a payment. Amounts are whole shillings.
  def stk_push(phone:, amount:, reference:, description:, callback_url:)
    post "/mpesa/stkpush/v1/processrequest", password_fields.merge(
      TransactionType: shortcode.daraja_transaction_type, Amount: amount, PartyA: phone, PartyB: shortcode.party_b,
      PhoneNumber: phone, CallBackURL: callback_url, AccountReference: reference.to_s.first(12), TransactionDesc: description.to_s.first(13)
    ), success: ->(body) { body["ResponseCode"].to_s == "0" }
  end

  # Whether a prompt was paid, cancelled or is still waiting; used when a callback doesn't arrive.
  def stk_query(checkout_request_id)
    post "/mpesa/stkpushquery/v1/query", password_fields.merge(CheckoutRequestID: checkout_request_id), success: ->(_) { true }
  end

  # Tells Safaricom where to send payments made straight to the Paybill or Till.
  def register_c2b_urls(confirmation_url:, validation_url:)
    post "/mpesa/c2b/v2/registerurl", { ShortCode: shortcode.party_b, ResponseType: "Completed",
      ConfirmationURL: confirmation_url, ValidationURL: validation_url }, success: ->(body) { body["ResponseCode"].to_s == "0" }
  end

  private
    def post(path, fields, success:)
      response = http.request(:post, url(path), headers: { "Authorization" => "Bearer #{access_token}" }, json: fields)
      return response.body if response.success? && success.(response.body)

      raise Refused, response.body["errorMessage"] || response.body["ResponseDescription"] || response.body["CustomerMessage"] || "Safaricom said no (#{response.status})"
    end

    def password_fields
      timestamp = Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S")
      { BusinessShortCode: shortcode.shortcode, Password: Base64.strict_encode64("#{shortcode.shortcode}#{shortcode.passkey}#{timestamp}"), Timestamp: timestamp }
    end

    def url(path)
      "#{BASE_URLS.fetch(shortcode.environment, BASE_URLS["sandbox"])}#{path}"
    end

    def http
      shortcode.simulator? ? Mpesa::Simulator.new(shortcode) : transport
    end
end
