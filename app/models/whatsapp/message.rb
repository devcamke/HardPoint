# One document or reminder sent on WhatsApp for a shop, and what became of it. Made by Whatsapp::Message.deliver_for,
# sent by Whatsapp::DeliveryJob, and updated by Meta's status webhook (sent → delivered → read, or failed).
class Whatsapp::Message < ApplicationRecord
  self.table_name = "whatsapp_messages"
  include AccountOwned

  STATUSES = %w[ queued sent delivered read failed simulated ].freeze
  # Meta's statuses only move forward.
  PROGRESS = %w[ queued sent delivered read ].freeze

  belongs_to :document, polymorphic: true, optional: true
  belongs_to :document_share, optional: true
  belongs_to :sent_by, class_name: "User", optional: true, default: -> { Current.user }

  validates :template, inclusion: { in: Whatsapp::TEMPLATES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :to_phone, format: { with: /\A\d{11,15}\z/, message: "isn't a phone number WhatsApp can reach" }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_document, ->(record) { where(document: record) }

  # Sends a document (receipt, quote or order, invoice, credit note, statement) to a phone: a share link Meta fetches
  # the PDF from, and a message queued to go. Returns the message, with errors if it can't go.
  def self.deliver_document(record, phone:, name: nil, from: nil, to: nil, template: "hardpoint_document")
    message = new(document: record, template: template, to_phone: Whatsapp.recipient(phone).to_s, recipient_name: name)
    message.errors.add :base, "WhatsApp isn't set up on this server yet" unless Whatsapp.available?
    return message if message.errors.any? || message.invalid?

    transaction do
      message.document_share = DocumentShare.create_for!(record, from: from, to: to)
      message.save!
    end
    Whatsapp::DeliveryJob.perform_later(message)
    message
  end

  # A customer's balance, with the statement attached: what's due, and how much of it is past its terms.
  def self.deliver_balance_reminder(customer)
    deliver_document(customer, phone: customer.phone, name: customer.name, template: "hardpoint_balance_reminder",
      from: Date.current.beginning_of_month - 2.months, to: Date.current)
  end

  def send_now
    return unless status == "queued"

    if Whatsapp.simulated?
      update!(status: "simulated", sent_at: Time.current, provider_message_id: "simulated-#{SecureRandom.hex(8)}")
    else
      id = Whatsapp::Client.new.send_template(to: to_phone, template: template, parameters: parameters,
        document_url: document_share.url(format: :pdf), filename: document_share.pdf_filename)
      update!(status: "sent", sent_at: Time.current, provider_message_id: id)
    end
  rescue Whatsapp::Client::Refused => refused
    update!(status: "failed", error: refused.message.first(250))
  end

  # A status from Meta's webhook, kept only if it moves the message on (a late "sent" doesn't undo "read").
  def record_status(status, at:, error: nil)
    if status == "failed"
      update!(status: "failed", error: error.to_s.first(250).presence || "WhatsApp couldn't deliver it")
    elsif PROGRESS.index(status).to_i > PROGRESS.index(self.status).to_i
      update!(status: status, "#{status}_at": at, sent_at: sent_at || at)
    end
  end

  def label
    { "queued" => "Sending", "sent" => "Sent", "delivered" => "Delivered", "read" => "Read", "failed" => "Not delivered", "simulated" => "Test mode" }.fetch(status)
  end

  def tone
    { "read" => :success, "delivered" => :success, "failed" => :danger, "simulated" => :muted }.fetch(status, :neutral)
  end

  private
    def parameters
      share = document_share
      if template == "hardpoint_balance_reminder"
        customer = share.document
        overdue = customer.overdue_cents
        [ account.name, customer.name, Money.format(customer.balance_cents, currency: account.currency), Money.format(overdue, currency: account.currency) ]
      else
        [ account.name, share.document_label, share.document_reference, share.document_amount ]
      end
    end
end
