# Goods from a completed sale going out on the shop's vehicle: pending until it leaves the yard
# (dispatched, with driver and vehicle), then delivered with the name of whoever received it and,
# optionally, a photo of the signed note as proof of delivery. A note carries some or all of the
# sale (its lines), so a sale can go out in parts, each note printing what's on the lorry.
class DeliveryNote < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :branch
  belongs_to :sale
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  # Transport charged when the note is made after the sale: an order for the customer, collected like any other.
  belongs_to :transport_order, class_name: "CustomerOrder", optional: true
  has_many :lines, -> { order(:id) }, class_name: "DeliveryNoteLine", dependent: :destroy, inverse_of: :delivery_note
  has_one_attached :proof_photo

  enum :status, %w[ pending dispatched delivered cancelled ].index_by(&:itself), default: :pending

  money_attribute :transport_charge

  accepts_nested_attributes_for :lines, reject_if: ->(attributes) { attributes["quantity"].to_d.zero? }

  validates :address, presence: true
  validates_same_account :sale
  validate(on: :create) { errors.add :sale, "must be a completed sale" unless sale&.completed? }
  validates :transport_charge_cents, numericality: { greater_than_or_equal_to: 0 }
  validate(on: :create) do
    if transport_charge_cents.positive? && sale && sale.customer.nil?
      errors.add :transport_charge, "needs a named customer to charge it to; for a walk-in sale, add transport at the till before payment"
    end
  end
  validate(on: :create) { errors.add :base, "Everything on this sale has already been put on a delivery note" if sale&.completed? && lines.empty? }
  validate { errors.add :proof_photo, "must be a photo (JPEG, PNG, WebP or HEIC)" if proof_photo.attached? && !proof_photo.content_type.in?(%w[ image/jpeg image/png image/webp image/heic ]) }

  before_validation(on: :create) do
    self.transport_charge_cents ||= 0
    self.branch ||= sale&.branch
    self.address = sale&.customer&.address if address.blank?
    self.contact_phone = sale&.customer&.phone if contact_phone.blank?
    carry_the_rest if lines.empty? && sale&.completed?
  end
  before_create { self.number = DocumentSequence.next_number(branch, "delivery_note") }
  after_create { track_event "created", receipt_number: sale.receipt_number }
  after_create :charge_transport, if: -> { transport_charge_cents.positive? }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :outstanding, -> { where(status: %w[ pending dispatched ]) }

  delegate :customer, to: :sale

  # { sale line id => quantity } of the sale not yet on a live delivery note (cancelled notes don't count),
  # leaving out lines with nothing left. `except` is a note being made or checked, so it doesn't count itself.
  def self.undelivered_by_line(sale, except: nil)
    notes = sale.delivery_notes.where.not(status: "cancelled")
    notes = notes.where.not(id: except.id) if except&.persisted?
    carried = DeliveryNoteLine.where(delivery_note: notes).group(:sale_line_id).sum(:quantity)
    sale.lines.to_h { [ _1.id, _1.quantity - carried.fetch(_1.id, 0) ] }.select { _2.positive? }
  end

  def reference
    "#{branch.code}-DN#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  # What the customer pays for transport: on the sale itself, or charged on this note.
  def transport_cents
    sale.transport_cents + transport_charge_cents
  end

  # Whether this note carries less than the whole sale.
  def partial?
    lines.sum(&:quantity) < sale.lines.sum(&:quantity)
  end

  def dispatch(driver_name:, vehicle: nil)
    return false unless pending?

    if driver_name.blank?
      errors.add :driver_name, "can't be blank"
      return false
    end

    update(status: :dispatched, driver_name: driver_name, vehicle: vehicle, dispatched_at: Time.current)
      .tap { |dispatched| track_event "dispatched", driver: driver_name, vehicle: vehicle if dispatched }
  end

  def deliver(received_by:, proof_photo: nil)
    return false unless dispatched?

    if received_by.blank?
      errors.add :received_by, "can't be blank"
      return false
    end

    self.proof_photo = proof_photo if proof_photo.present?
    update(status: :delivered, received_by: received_by, delivered_at: Time.current)
      .tap { |delivered| track_event "delivered", received_by: received_by if delivered }
  end

  # Cancelling the trip cancels the transport charged for it too, while it's still an open order. A deposit
  # held on it has to be refunded first; transport already paid at the till (the order collected) is a sale
  # of its own, so it stays and the event says which receipt to refund it from.
  def cancel
    return false unless pending? || dispatched?

    transaction do
      if transport_order&.takes_deposits?
        transport_order.cancel(reason: "#{reference} cancelled") or raise ActiveRecord::RecordInvalid, transport_order
      end
      update!(status: :cancelled)
      paid_on = transport_order.sales.find_by(status: "completed")&.receipt_number if transport_order&.collected?
      track_event "cancelled", transport_order: transport_order&.reference, transport_paid_on: paid_on
    end
    true
  rescue ActiveRecord::RecordInvalid => invalid
    errors.add :base, "The transport order #{transport_order.reference} couldn't be cancelled: #{invalid.record.errors.full_messages.to_sentence}"
    false
  end

  private
    # A note made without choosing lines takes everything of the sale not yet on another note.
    def carry_the_rest
      self.class.undelivered_by_line(sale, except: self).each do |sale_line_id, quantity|
        lines.build(account: account, sale_line_id: sale_line_id, quantity: quantity)
      end
    end

    # A confirmed order for the trip, so it's collected at the till (cash, M-Pesa, Airtel Money or the
    # customer's account) with its own receipt and eTIMS invoice.
    def charge_transport
      order = account.customer_orders.create!(branch: branch, customer: customer, job: sale.job, note: "Transport for #{reference}",
        lines_attributes: [ { account: account, product: account.transport_product, quantity: 1, unit_price_cents: transport_charge_cents,
                              detail: "#{reference} to #{address.first(80)}" } ])
      order.confirm or raise ActiveRecord::RecordInvalid, order
      update_column(:transport_order_id, order.id)
      self.transport_order = order
    end
end
