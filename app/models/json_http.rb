require "net/http"

# JSON over HTTPS on Net::HTTP, for the M-Pesa, eTIMS and SMS integrations. Integrations take their
# transport as a setting, so tests and the built-in simulators stand in for the network.
class JsonHttp
  Response = Data.define(:status, :body) do
    def success? = status.between?(200, 299)
  end

  # The provider couldn't be reached, or didn't answer in time: worth trying again later.
  Unreachable = Class.new(StandardError)

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 30

  def request(method, url, headers: {}, json: nil, form: nil)
    uri = URI(url)
    request = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri, headers)
    if json
      request["Content-Type"] = "application/json"
      request.body = json.to_json
    elsif form
      request.set_form_data(form)
    end

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
    Response.new(response.code.to_i, parse(response.body))
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError => error
    raise Unreachable, "#{uri.host}: #{error.message}"
  end

  private
    def parse(body)
      body.present? ? JSON.parse(body) : {}
    rescue JSON::ParserError
      { "raw" => body.to_s.first(500) }
    end
end
