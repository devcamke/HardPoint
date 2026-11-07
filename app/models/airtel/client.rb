# Airtel Africa's Open API (Collection) for one merchant account. Each call gets a fresh OAuth token.
# The paths are Airtel's v1 Collection API; they live here so a change on Airtel's side is one edit.
class Airtel::Client
  BASE_URLS = { "sandbox" => "https://openapiuat.airtel.africa", "production" => "https://openapi.airtel.africa" }.freeze
  TOKEN_PATH = "/auth/oauth2/token"
  PAYMENT_PATH = "/merchant/v1/payments/"
  STATUS_PATH = "/standard/v1/payments/%s"
  COUNTRY = "KE"
  CURRENCY = "KES"

  # Airtel refused the request (bad credentials, wrong number…); retrying won't help.
  Refused = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  attr_reader :merchant

  def initialize(merchant)
    @merchant = merchant
  end

  def access_token
    response = http.request(:post, url(TOKEN_PATH), headers: { "Accept" => "*/*" },
      json: { client_id: merchant.client_id, client_secret: merchant.client_secret, grant_type: "client_credentials" })
    response.body["access_token"] or raise Refused, "Airtel didn't accept the client ID and secret (#{response.status})"
  end

  # Asks the customer's phone to approve a payment. msisdn is the number without 254; amounts are whole shillings.
  def request_payment(msisdn:, amount:, transaction_id:, reference:)
    response = http.request(:post, url(PAYMENT_PATH), headers: headers, json: {
      reference: reference.to_s.first(64),
      subscriber: { country: COUNTRY, currency: CURRENCY, msisdn: msisdn },
      transaction: { amount: amount, country: COUNTRY, currency: CURRENCY, id: transaction_id }
    })
    return response.body if response.success? && response.body.dig("status", "success").to_s == "true"

    raise Refused, response.body.dig("status", "message").presence || "Airtel said no (#{response.status})"
  end

  # Where a payment stands: { "status" => "TS" | "TF" | "TIP" | …, "airtel_money_id" => …, "message" => … }.
  def status(transaction_id)
    response = http.request(:get, url(format(STATUS_PATH, transaction_id)), headers: headers)
    raise Refused, response.body.dig("status", "message").presence || "Airtel said no (#{response.status})" unless response.success?

    response.body.dig("data", "transaction") || {}
  end

  private
    def headers
      { "Authorization" => "Bearer #{access_token}", "X-Country" => COUNTRY, "X-Currency" => CURRENCY, "Accept" => "*/*" }
    end

    def url(path)
      "#{BASE_URLS.fetch(merchant.environment, BASE_URLS["sandbox"])}#{path}"
    end

    def http
      merchant.simulator? ? Airtel::Simulator.new(merchant) : transport
    end
end
