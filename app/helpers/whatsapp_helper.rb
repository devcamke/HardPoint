# "WhatsApp" buttons that open a chat with the message written and a link to the document (DocumentShare).
# With the customer's or supplier's mobile number the chat opens with them; without one, WhatsApp asks who to send it to.
module WhatsappHelper
  def whatsapp_button(record, phone: nil, from: nil, to: nil, label: "WhatsApp", **options)
    link_to label, whatsapp_url(phone, whatsapp_message(record, from:, to:)), target: "_blank", rel: "noopener",
      class: options.delete(:class) || "btn-secondary", title: "Send on WhatsApp", **options
  end

  def whatsapp_url(phone, text)
    "https://wa.me/#{PhoneNumber.normalize(phone)}?#{{ text: text }.to_query}"
  end

  def shared_document_url(record, from: nil, to: nil)
    share_url(DocumentShare.token_for(record, from:, to:), subdomain: Current.account.subdomain)
  end

  def whatsapp_message(record, from: nil, to: nil)
    shop = Current.account.name
    link = shared_document_url(record, from:, to:)

    case record
    when Sale
      "#{shop}: your receipt #{record.receipt_number} for #{money(record.total_cents)}. #{link}"
    when CustomerOrder
      if record.quote?
        "#{shop}: quote #{record.reference} for #{money(record.total_cents)}" \
          "#{", valid until #{l(record.valid_until, format: :long)}" if record.valid_until}. #{link}"
      else
        "#{shop}: your order #{record.reference} for #{money(record.total_cents)}. #{link}"
      end
    when Customer
      statement = record.statement(from: from || Date.current.beginning_of_month, to: to || Date.current)
      paybill = Current.account.mpesa_shortcodes.for_branch(nil)
      "#{shop}: statement for #{record.name}, #{l(statement.from, format: :long)} to #{l(statement.to, format: :long)}. " \
        "Balance #{money(statement.closing_balance_cents)}." \
        "#{" Pay to #{paybill.label}, account #{PhoneNumber.display(record.phone).to_s.delete(" ")}." if paybill && record.phone.present?} #{link}"
    when PurchaseOrder
      "#{shop}: purchase order #{record.reference} (#{money(record.total_cents, currency: record.currency)})" \
        "#{", please deliver to #{record.branch.name} by #{l(record.expected_on, format: :long)}" if record.expected_on}. #{link}"
    when DeliveryNote
      "#{shop}: delivery note #{record.reference} for your goods to #{record.address}. #{link}"
    end
  end
end
