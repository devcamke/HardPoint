# Stands in for KRA on a "simulator" device (demo shops and development), answering like OSCU.
class Etims::Simulator
  def initialize(device)
    @device = device
  end

  def request(_method, url, json: {}, **)
    data = case URI(url).path.delete_prefix("/etims-api")
    when "/selectInitOsdcInfo"
      { info: { tin: @device.tin, bhfId: @device.bhf_id, sdcId: "KRACU0300000#{@device.id.to_s.rjust(3, "0")}", mrcNo: "WIS01000#{@device.id.to_s.rjust(4, "0")}",
                cmcKey: SecureRandom.hex(16).upcase } }
    when "/saveTrnsSalesOsdc"
      { curRcptNo: json[:invcNo], totRcptNo: json[:invcNo], intrlData: SecureRandom.alphanumeric(26).upcase,
        rcptSign: SecureRandom.alphanumeric(16).upcase, sdcDateTime: Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S") }
    end
    JsonHttp::Response.new(200, { "resultCd" => "000", "resultMsg" => "It is succeeded", "data" => data&.deep_stringify_keys })
  end
end
