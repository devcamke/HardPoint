# An order to a supplier for delivery to a branch: a draft while it's being put together, sent
# (emailed as a PDF), then partially or fully received through goods received notes.
class PurchaseOrder < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :branch
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, -> { order(:id) }, class_name: "PurchaseOrderLine", dependent: :destroy, inverse_of: :purchase_order
  has_many :goods_receipts, dependent: :restrict_with_error

  enum :status, %w[ draft sent partially_received received cancelled ].index_by(&:itself), default: :draft

  money_attribute :total

  accepts_nested_attributes_for :lines, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["product_code"].blank? && attributes["quantity"].blank? }

  validates_same_account :supplier, :branch
  validate { errors.add :base, "Add at least one product" if lines.reject(&:marked_for_destruction?).empty? }
  validate :no_duplicate_products
  validate(on: :update) { errors.add :base, "Only a draft can be changed" if lines.any?(&:changed_for_autosave?) && status_was != "draft" }

  before_create { self.number = DocumentSequence.next_number(branch, "purchase_order") }
  before_save { self.total_cents = lines.reject(&:marked_for_destruction?).sum(&:line_total_cents) }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :open, -> { where(status: %w[ sent partially_received ]) }

  def reference
    "#{branch.code}-PO#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  def receivable?
    sent? || partially_received?
  end

  def outstanding_lines
    lines.select { _1.outstanding_quantity.positive? }
  end

  def mark_sent
    draft? && update(status: :sent, sent_at: Time.current).tap { |sent| track_event "sent", supplier: supplier.name, total: total_cents if sent }
  end

  def cancel
    (draft? || sent?) && update(status: :cancelled).tap { |cancelled| track_event "cancelled" if cancelled }
  end

  def refresh_receipt_status
    lines.reload
    update!(status: lines.all? { _1.outstanding_quantity <= 0 } ? :received : :partially_received)
  end

  private
    def no_duplicate_products
      duplicates = lines.reject(&:marked_for_destruction?).filter_map(&:product).tally.select { |_, count| count > 1 }.keys
      errors.add :base, "#{duplicates.map(&:name).to_sentence} is listed more than once" if duplicates.any?
    end
end
