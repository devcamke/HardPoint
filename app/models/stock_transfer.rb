# Moves stock between branches. Sending takes it out of the source branch straight away; it's
# "in transit" until the other branch receives it (or the transfer is cancelled and it goes back).
class StockTransfer < ApplicationRecord
  include AccountOwned, Eventable

  belongs_to :from_branch, class_name: "Branch"
  belongs_to :to_branch, class_name: "Branch"
  belongs_to :sender, class_name: "User", default: -> { Current.user }, optional: true
  belongs_to :receiver, class_name: "User", optional: true
  has_many :lines, class_name: "StockTransferLine", dependent: :destroy, inverse_of: :stock_transfer

  enum :status, %w[ in_transit received cancelled ].index_by(&:itself), default: :in_transit

  accepts_nested_attributes_for :lines, reject_if: ->(attributes) { attributes["product_code"].blank? && attributes["quantity"].blank? }

  validates_same_account :from_branch, :to_branch
  validate { errors.add :to_branch, "must be a different branch" if from_branch_id.present? && from_branch_id == to_branch_id }
  validate { errors.add :base, "Add at least one product" if lines.reject(&:marked_for_destruction?).empty? }
  validate do
    duplicates = lines.filter_map(&:product).tally.select { |_, count| count > 1 }.keys
    errors.add :base, "#{duplicates.map(&:name).to_sentence} is listed more than once" if duplicates.any?
  end

  before_create { self.sent_at = Time.current }
  after_create :send_stock

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def receive(user = Current.user)
    with_lock do
      return false unless in_transit?

      lines.each { |line| line.product.move_stock(branch: to_branch, quantity: line.quantity, reason: "transfer_in", source: self, creator: user, reverses: { taken_by: self }) }
      update! status: :received, receiver: user, received_at: Time.current
      track_event "received"
    end
  end

  def cancel(user = Current.user)
    with_lock do
      return false unless in_transit?

      lines.each { |line| line.product.move_stock(branch: from_branch, quantity: line.quantity, reason: "transfer_returned", source: self, creator: user, reverses: { taken_by: self }) }
      update! status: :cancelled
      track_event "cancelled"
    end
  end

  def name
    "##{id} #{from_branch.name} → #{to_branch.name}"
  end

  private
    def send_stock
      lines.each { |line| line.product.move_stock(branch: from_branch, quantity: -line.quantity, reason: "transfer_out", source: self, creator: sender) }
      track_event "sent"
    end
end
