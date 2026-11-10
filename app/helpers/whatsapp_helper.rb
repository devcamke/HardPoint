# "WhatsApp" buttons that make a link to the document (DocumentShare) and open a chat with the message written.
# With the customer's or supplier's mobile number the chat opens with them; without one, WhatsApp asks who to send it to.
module WhatsappHelper
  def whatsapp_button(record, phone: nil, from: nil, to: nil, label: "WhatsApp", **options)
    kind = DocumentShare::KINDS.key(record.class.name)
    button_to label, document_shares_path, params: { kind: kind, id: record.id, phone: phone, from: from, to: to }.compact,
      class: options.delete(:class) || "btn-secondary", title: "Send on WhatsApp",
      form: { target: "_blank", data: { turbo: false } }, **options
  end

  # The links already sent for a document, newest first, each with a button to take it back, and what HardPoint sent
  # on WhatsApp with whether it's been delivered and read.
  def shared_links(record)
    shares = Current.account.document_shares.for_document(record).newest_first.includes(:created_by).to_a
    messages = feature?(:whatsapp_messages) ? Current.account.whatsapp_messages.for_document(record).newest_first.includes(:sent_by).limit(5).to_a : []
    safe_join([ (render "whatsapp_messages/sent", messages: messages if messages.any?), (render "shares/list", shares: shares if shares.any?) ].compact)
  end
end
