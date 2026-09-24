# Goods from a completed sale going out on the shop's vehicle: pending until it leaves the yard
# (dispatched, with driver and vehicle), then delivered with the name of whoever received it and,
# optionally, a photo of the signed note as proof of delivery.
class DeliveryNote < ApplicationRecord
  include AccountOwned, Eventable

  belongs_to :branch
  belongs_to :sale
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_one_attached :proof_photo

  enum :status, %w[ pending dispatched delivered cancelled ].index_by(&:itself), default: :pending

  validates :address, presence: true
  validates_same_account :sale
  validate(on: :create) { errors.add :sale, "must be a completed sale" unless sale&.completed? }
  validate { errors.add :proof_photo, "must be a photo (JPEG, PNG, WebP or HEIC)" if proof_photo.attached? && !proof_photo.content_type.in?(%w[ image/jpeg image/png image/webp image/heic ]) }

  before_validation(on: :create) do
    self.branch ||= sale&.branch
    self.address = sale&.customer&.address if address.blank?
    self.contact_phone = sale&.customer&.phone if contact_phone.blank?
  end
  before_create { self.number = DocumentSequence.next_number(branch, "delivery_note") }
  after_create { track_event "created", receipt_number: sale.receipt_number }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :outstanding, -> { where(status: %w[ pending dispatched ]) }

  delegate :customer, to: :sale

  def reference
    "#{branch.code}-DN#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

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

  def cancel
    (pending? || dispatched?) && update(status: :cancelled).tap { |cancelled| track_event "cancelled" if cancelled }
  end
end
