# The OSCU API for one branch's control unit.
class Etims::Client
  BASE_URLS = { "sandbox" => "https://etims-api-sbx.kra.go.ke/etims-api", "production" => "https://etims-api.kra.go.ke/etims-api" }.freeze

  # KRA refused the request (e.g. an unknown item class, a device not registered). Retrying
  # unchanged won't help; the reason goes on the submission for someone to fix.
  Refused = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  attr_reader :device

  def initialize(device)
    @device = device
  end

  # First contact: KRA returns the communication key and control unit IDs for this device.
  def initialize_device
    post("/selectInitOsdcInfo", { tin: device.tin, bhfId: device.bhf_id, dvcSrlNo: device.serial_number }, authenticated: false).dig("data", "info")
  end

  def save_item(fields)
    post "/saveItem", fields
  end

  def save_sales(fields)
    post("/saveTrnsSalesOsdc", fields)["data"]
  end

  private
    def post(path, fields, authenticated: true)
      headers = { "tin" => device.tin, "bhfId" => device.bhf_id }
      headers["cmcKey"] = device.cmc_key if authenticated
      response = http.request(:post, "#{BASE_URLS.fetch(device.environment, BASE_URLS["sandbox"])}#{path}", headers: headers,
        json: fields.merge(tin: device.tin, bhfId: device.bhf_id))

      raise JsonHttp::Unreachable, "KRA answered #{response.status}" if response.status >= 500
      return response.body if response.body["resultCd"] == "000"

      raise Refused, [ response.body["resultCd"], response.body["resultMsg"] || "KRA said no (#{response.status})" ].compact.join(": ")
    end

    def http
      device.simulator? ? Etims::Simulator.new(device) : transport
    end
end
