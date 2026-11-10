# Sends a template message through the WhatsApp Cloud API. Raised errors say what Meta answered.
class Whatsapp::Client
  Refused = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  # Returns Meta's message id. The document is a link Meta fetches (a PDF on a share link).
  def send_template(to:, template:, parameters:, document_url: nil, filename: nil)
    response = transport.request(:post, "#{Whatsapp::GRAPH_URL}/#{Whatsapp.graph_version}/#{Whatsapp.phone_number_id}/messages",
      headers: { "Authorization" => "Bearer #{Whatsapp.access_token}" }, json: payload(to, template, parameters, document_url, filename))
    raise Refused, response.body.dig("error", "message").presence || "WhatsApp said no (#{response.status})" unless response.success?

    response.body.dig("messages", 0, "id") or raise Refused, "WhatsApp didn't return a message id"
  end

  private
    def payload(to, template, parameters, document_url, filename)
      components = []
      components << { type: "header", parameters: [ { type: "document", document: { link: document_url, filename: filename } } ] } if document_url
      components << { type: "body", parameters: parameters.map { { type: "text", text: _1.to_s.first(1000) } } }
      { messaging_product: "whatsapp", recipient_type: "individual", to: to, type: "template",
        template: { name: template, language: { code: Whatsapp.language }, components: components } }
    end
end
