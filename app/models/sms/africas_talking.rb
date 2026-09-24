# Africa's Talking's SMS API. Credentials live in the platform's Rails credentials under
# africas_talking: { username:, api_key:, sender_id: } ("sandbox" as the username uses their sandbox).
class Sms::AfricasTalking
  Refused = Class.new(StandardError)
  Receipt = Data.define(:message_id, :cost)

  # 100 processed, 101 sent, 102 queued.
  ACCEPTED_STATUS_CODES = [ 100, 101, 102 ].freeze

  class_attribute :transport, default: JsonHttp.new

  def deliver(to:, message:)
    fields = { username: credentials[:username], to: "+#{to}", message: message, from: credentials[:sender_id] }.compact_blank
    response = http.request(:post, url, headers: { "apiKey" => credentials[:api_key].to_s, "Accept" => "application/json" }, form: fields)
    recipient = Array(response.body.dig("SMSMessageData", "Recipients")).first

    if recipient && recipient["statusCode"].to_i.in?(ACCEPTED_STATUS_CODES)
      Receipt.new(recipient["messageId"], recipient["cost"])
    else
      raise Refused, recipient&.dig("status") || response.body.dig("SMSMessageData", "Message") || "Africa's Talking said no (#{response.status})"
    end
  end

  private
    def credentials
      Rails.application.credentials.africas_talking || {}
    end

    def url
      host = credentials[:username] == "sandbox" ? "api.sandbox.africastalking.com" : "api.africastalking.com"
      "https://#{host}/version1/messaging"
    end

    # Development and tests keep texts in the outbox instead of sending them.
    def http
      Rails.configuration.x.sms_outbox ? Sms::Outbox : transport
    end
end
