# A link to one document that anyone holding it can open for 30 days, without signing in: what goes in a
# WhatsApp message to a customer or supplier. The token is signed and names the shop, the kind of document
# and its id (and, for a statement, its period), so it opens that document only, and only at its own shop.
class DocumentShare
  KINDS = { "receipt" => "Sale", "order" => "CustomerOrder", "statement" => "Customer",
            "purchase_order" => "PurchaseOrder", "delivery_note" => "DeliveryNote" }.freeze
  EXPIRES_IN = 30.days

  attr_reader :kind, :record, :from, :to

  def self.token_for(record, from: nil, to: nil)
    kind = KINDS.key(record.class.name) or raise ArgumentError, "#{record.class} can't be shared"
    payload = { "k" => kind, "id" => record.id, "a" => record.account_id, "from" => from&.iso8601, "to" => to&.iso8601 }.compact
    verifier.generate(payload, expires_in: EXPIRES_IN, purpose: :share)
  end

  # The share a token stands for at this shop, or nil if it's forged, expired, or another shop's.
  def self.find(token, account)
    payload = verifier.verified(token.to_s, purpose: :share)
    return unless payload.is_a?(Hash) && payload["a"] == account.id && (model = KINDS[payload["k"]])

    record = model.constantize.where(account: account).find_by(id: payload["id"])
    new(payload["k"], record, payload["from"], payload["to"]) if record
  rescue ArgumentError
    nil
  end

  def self.verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("document shares"), url_safe: true, serializer: JSON)
  end

  def initialize(kind, record, from, to)
    @kind, @record = kind, record
    @from, @to = (Date.iso8601(from) if from), (Date.iso8601(to) if to)
  end

  # The PDF for every kind except a receipt, which opens as the till's receipt page.
  def pdf
    case kind
    when "order" then CustomerOrderPdf.new(record)
    when "purchase_order" then PurchaseOrderPdf.new(record)
    when "delivery_note" then DeliveryNotePdf.new(record)
    when "statement"
      StatementPdf.new(record.statement(from: from || Date.current.beginning_of_month, to: to || Date.current),
        branch: record.account.branches.alphabetically.first)
    end
  end
end
