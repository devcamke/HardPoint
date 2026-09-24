# A sale, void or return on its way to KRA, and what KRA signed. Invoice numbers are gap-free per
# control unit and fixed when the submission is queued. Sending is retried with growing gaps
# while KRA can't be reached; a refusal waits for someone to fix the cause and retry.
class Etims::Submission < ApplicationRecord
  include AccountOwned

  KINDS = %w[ sale credit_note ].freeze
  MAX_RETRY_GAP = 6.hours

  belongs_to :device
  belongs_to :document, polymorphic: true

  enum :status, %w[ pending sent failed ].index_by(&:itself), default: :pending

  validates :kind, inclusion: { in: KINDS }

  before_validation(on: :create) { self.invoice_number ||= DocumentSequence.next_number(device.branch, "etims_invoice") }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  # Queues a document if its branch has a control unit. A credit note is only needed when the
  # original sale went to KRA.
  def self.queue(document, kind:)
    device = Etims::Device.for_branch(document.branch) or return
    original = original_for(document) if kind == "credit_note"
    return if kind == "credit_note" && original.nil?

    submission = create!(account: document.account, device: device, document: document, kind: kind, original_invoice_number: original&.invoice_number)
    Etims::TransmitJob.perform_later(submission)
    submission
  rescue ActiveRecord::RecordNotUnique
    find_by(document: document, kind: kind)
  end

  def self.original_for(document)
    find_by(document: document.is_a?(SaleReturn) ? document.sale : document, kind: "sale")
  end

  def transmit
    return if sent?

    # Counted outside the lock, so an attempt that fails still counts towards the next gap.
    update!(attempts: attempts + 1, last_attempted_at: Time.current)
    with_lock do
      return if sent?
      return update!(status: :failed, last_error: "Set up the control unit with KRA first (Settings › KRA eTIMS)") unless device.initialized?
      return update!(last_error: "Waiting for the original sale to reach KRA") if credit_note? && !original&.sent?

      invoice = Etims::Invoice.new(self)
      invoice.products.each { device.register(_1) }
      data = device.client.save_sales(invoice.to_h)
      update!(status: :sent, sent_at: Time.current, last_error: nil, receipt_number: data["curRcptNo"], total_receipt_number: data["totRcptNo"],
        internal_data: data["intrlData"], receipt_signature: data["rcptSign"], sdc_date_time: data["sdcDateTime"])
    end
  rescue Etims::Client::Refused => error
    update!(status: :failed, last_error: error.message.first(250))
  rescue JsonHttp::Unreachable => error
    update!(last_error: "KRA couldn't be reached: #{error.message}".first(250))
  end

  def retry_now
    update!(status: :pending, last_error: nil) if failed?
    Etims::TransmitJob.perform_later(self)
  end

  # Waits 2, 4, 8… minutes between attempts, up to six hours.
  def due_for_retry?
    pending? && (last_attempted_at.nil? || last_attempted_at < [ (2**attempts).minutes, MAX_RETRY_GAP ].min.ago)
  end

  def credit_note? = kind == "credit_note"

  def original
    self.class.find_by(device: device, invoice_number: original_invoice_number) if original_invoice_number
  end

  def verification_url
    device.verification_url(receipt_signature) if sent?
  end

  def document_label
    case document
    when SaleReturn then "Return #{document.return_number}"
    when Sale then credit_note? ? "Void of #{document.receipt_number}" : "Sale #{document.receipt_number}"
    end
  end

  def signed_at
    Time.find_zone("Nairobi").strptime(sdc_date_time, "%Y%m%d%H%M%S") if sdc_date_time.present?
  rescue ArgumentError
    nil
  end
end
