# Stands in for Airtel on a "simulator" merchant (demo shops and development), answering as the Open API
# does. A prompt is approved a few seconds later through the same code as a real callback; numbers ending
# 0000 decline, to show what that looks like.
class Airtel::Simulator
  def initialize(merchant)
    @merchant = merchant
  end

  def request(_method, url, json: nil, **)
    path = URI(url).path
    body = if path == Airtel::Client::TOKEN_PATH
      { "access_token" => "simulated", "expires_in" => "180", "token_type" => "bearer" }
    elsif path == Airtel::Client::PAYMENT_PATH
      Airtel::SimulatedCallbackJob.set(wait: 4.seconds).perform_later(@merchant, json.dig(:transaction, :id), json.dig(:subscriber, :msisdn).to_s)
      { "data" => { "transaction" => { "id" => json.dig(:transaction, :id), "status" => "Success." } },
        "status" => { "code" => "200", "message" => "SUCCESS", "result_code" => "ESB000010", "success" => true } }
    else
      { "data" => { "transaction" => { "id" => path.split("/").last, "status" => "TIP", "message" => "In progress" } },
        "status" => { "code" => "200", "message" => "SUCCESS", "success" => true } }
    end
    JsonHttp::Response.new(200, body)
  end
end
