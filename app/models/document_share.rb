# A link to one document that anyone holding it can open for 30 days, without signing in: what goes in a
# WhatsApp message to a customer or supplier. Each link is a row of its own, so the shop can see the links it
# has sent and revoke one, and a statement opens with the period it was sent with, not the period of the day
# it's opened. The token is random and only opens this document, at this shop.
class DocumentShare < ApplicationRecord
  include AccountOwned, Eventable

  KINDS = { "receipt" => "Sale", "order" => "CustomerOrder", "statement" => "Customer",
            "purchase_order" => "PurchaseOrder", "delivery_note" => "DeliveryNote" }.freeze
  EXPIRES_IN = 30.days

  belongs_to :document, polymorphic: true
  belongs_to :created_by, class_name: "User", default: -> { Current.user }

  has_secure_token :token, length: 32

  before_validation(on: :create) { self.expires_at ||= EXPIRES_IN.from_now }
  validates :document_type, inclusion: { in: KINDS.values }
  validate { errors.add :document, "must belong to this shop" if document && document.account_id != account_id }
  validate :statement_has_a_period

  scope :current, -> { where(revoked_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_document, ->(record) { where(document: record) }

  # A link for a record, with a statement fixed to its period (this month so far when none is given).
  def self.create_for!(record, from: nil, to: nil)
    kind = KINDS.key(record.class.name) or raise ArgumentError, "#{record.class} can't be shared"
    from, to = Date.current.beginning_of_month, Date.current if kind == "statement" && from.nil? && to.nil?
    create!(document: record, period_from: from, period_to: to).tap { _1.track_event "shared", kind: kind }
  end

  # The share a token stands for at this shop, counted as opened; nil if it's unknown, revoked, expired or another shop's.
  def self.open(token, account)
    share = account.document_shares.current.find_by(token: token.to_s) or return
    share.update_columns(opened_count: share.opened_count + 1, last_opened_at: Time.current)
    share
  end

  def kind = KINDS.key(document_type)
  def record = document
  def from = period_from
  def to = period_to
  def revoked? = revoked_at.present?
  def expired? = expires_at.past?
  def active? = !revoked? && !expired?

  def revoke
    update!(revoked_at: Time.current)
    track_event "share_revoked", kind: kind
  end

  def url
    Rails.application.routes.url_helpers.share_url(token, subdomain: account.subdomain, **Rails.configuration.x.webhook_url_options)
  end

  # What's written in the WhatsApp message for the person it's sent to.
  def message
    shop = account.name
    link = url
    case kind
    when "receipt"
      "#{shop}: your receipt #{document.receipt_number} for #{money(document.total_cents)}. #{link}"
    when "order"
      if document.quote?
        "#{shop}: quote #{document.reference} for #{money(document.total_cents)}" \
          "#{", valid until #{I18n.l(document.valid_until, format: :long)}" if document.valid_until}. #{link}"
      else
        "#{shop}: your order #{document.reference} for #{money(document.total_cents)}. #{link}"
      end
    when "statement"
      statement = document.statement(from: from, to: to)
      paybill = account.mpesa_shortcodes.for_branch(nil)
      "#{shop}: statement for #{document.name}, #{I18n.l(statement.from, format: :long)} to #{I18n.l(statement.to, format: :long)}. " \
        "Balance #{money(statement.closing_balance_cents)}." \
        "#{" Pay to #{paybill.label}, account #{PhoneNumber.display(document.phone).to_s.delete(" ")}." if paybill && document.phone.present?} #{link}"
    when "purchase_order"
      "#{shop}: purchase order #{document.reference} (#{money(document.total_cents, currency: document.currency)})" \
        "#{", please deliver to #{document.branch.name} by #{I18n.l(document.expected_on, format: :long)}" if document.expected_on}. #{link}"
    when "delivery_note"
      "#{shop}: delivery note #{document.reference} for your goods to #{document.address}. #{link}"
    end
  end

  # The PDF for every kind except a receipt, which opens as the till's receipt page.
  def pdf
    case kind
    when "order" then CustomerOrderPdf.new(document)
    when "purchase_order" then PurchaseOrderPdf.new(document)
    when "delivery_note" then DeliveryNotePdf.new(document)
    when "statement" then StatementPdf.new(document.statement(from: from, to: to), branch: account.branches.alphabetically.first)
    end
  end

  # "Receipt MAIN-000012", "Statement 1 Nov – 8 Nov 2026"
  def label
    case kind
    when "receipt" then "Receipt #{document.receipt_number}"
    when "statement" then "Statement #{I18n.l(from, format: :short)} to #{I18n.l(to, format: :short)}"
    else "#{kind.humanize} #{document.reference}"
    end
  end

  private
    def money(cents, currency: account.currency) = Money.format(cents, currency: currency)

    def statement_has_a_period
      errors.add :period_from, "is needed for a statement" if kind == "statement" && (from.nil? || to.nil?)
    end

    def event_name = label
end
