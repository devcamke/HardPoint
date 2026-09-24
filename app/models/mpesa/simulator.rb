# Stands in for Safaricom on a "simulator" shortcode (demo shops and development), answering
# like Daraja does. A prompt "reaches the phone" and is paid a few seconds later, through the same
# code as a real callback; numbers ending 0000 decline, to show what that looks like.
class Mpesa::Simulator
  def initialize(shortcode)
    @shortcode = shortcode
  end

  def request(_method, url, json: nil, **)
    path = URI(url).path
    body = case path
    when "/oauth/v1/generate" then { "access_token" => "simulated", "expires_in" => "3599" }
    when "/mpesa/stkpush/v1/processrequest" then prompt(json)
    when "/mpesa/stkpushquery/v1/query" then { "errorCode" => "500.001.1001", "errorMessage" => "The transaction is being processed" }
    when "/mpesa/c2b/v2/registerurl" then { "ResponseCode" => "0", "ResponseDescription" => "Success" }
    end
    JsonHttp::Response.new(200, body)
  end

  private
    def prompt(fields)
      checkout_request_id = "ws_CO_#{Time.current.strftime("%d%m%Y%H%M%S")}#{SecureRandom.random_number(10**9)}"
      Mpesa::SimulatedCallbackJob.set(wait: 4.seconds).perform_later(@shortcode, checkout_request_id, fields[:PhoneNumber].to_s, fields[:Amount].to_i)
      { "MerchantRequestID" => SecureRandom.hex(6), "CheckoutRequestID" => checkout_request_id, "ResponseCode" => "0",
        "ResponseDescription" => "Success. Request accepted for processing", "CustomerMessage" => "Success. Request accepted for processing" }
    end
end
