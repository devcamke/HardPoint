# Moves stock between branches. Sending takes it out of the source branch straight away; it's
# "in transit" until the other branch receives it (or the transfer is cancelled and it goes back).
# The receiving branch counts it in line by line: anything short was either lost on the way, and is
# written off there, or never left, and goes back into the sender's stock.
class StockTransfer < ApplicationRecord
  include AccountOwned, Eventable

  belongs_to :from_branch, class_name: "Branch"
  belongs_to :to_branch, class_name: "Branch"
  belongs_to :sender, class_name: "User", default: -> { Current.user }, optional: true
  belongs_to :receiver, class_name: "User", optional: true
  has_many :lines, class_name: "StockTransferLine", dependent: :destroy, inverse_of: :stock_transfer

  enum :status, %w[ in_transit received cancelled ].index_by(&:itself), default: :in_transit

  # What became of anything short when the transfer was received.
  SHORTFALLS = %w[ lost returned ].freeze
  validates :shortfall, inclusion: { in: SHORTFALLS }, allow_nil: true
  validate :receipt_adds_up, on: :receive

  accepts_nested_attributes_for :lines, reject_if: ->(attributes) { attributes["product_code"].blank? && attributes["quantity"].blank? }

  validates_same_account :from_branch, :to_branch
  validate { errors.add :to_branch, "must be a different branch" if from_branch_id.present? && from_branch_id == to_branch_id }
  validate { errors.add :base, "Add at least one product" if lines.reject(&:marked_for_destruction?).empty? }
  validate do
    duplicates = lines.filter_map(&:product).tally.select { |_, count| count > 1 }.keys
    errors.add :base, "#{duplicates.map(&:name).to_sentence} is listed more than once" if duplicates.any?
  end

  # Expired stock doesn't travel: another branch would only have to write it off.
  validate(on: :create) do
    lines.reject(&:marked_for_destruction?).each do |line|
      next unless line.product&.tracks_batches? && from_branch
      in_date = line.product.in_date_stock_at(from_branch)
      errors.add :base, "Only #{in_date.to_s("F").delete_suffix(".0")} #{line.product.name} at #{from_branch.name} are in date; write off the expired ones before sending" if line.quantity.to_d > in_date && line.quantity.to_d <= line.product.stock_at(from_branch)
    end
  end

  before_create { self.sent_at = Time.current }
  after_create :send_stock

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  # `received` is what arrived, by line id; lines not mentioned arrived in full. With anything short,
  # `shortfall` says what became of it: "lost" puts the whole line into stock at the receiving branch and
  # writes the missing part off there, so the ledger shows where it went; "returned" puts what never
  # left back into the sender's stock. Refused, with errors, when the quantities don't add up.
  def receive(user = Current.user, received: {}, shortfall: nil)
    with_lock do
      return false unless in_transit?

      received = received.to_h.transform_keys(&:to_s)
      lines.each { |line| line.received_quantity = received[line.id.to_s].presence&.to_d || line.quantity }
      self.shortfall = short? ? shortfall.presence : nil
      return false unless valid?(:receive)

      lines.each do |line|
        line.save!
        arriving = self.shortfall == "lost" ? line.quantity : line.received_quantity
        line.product.move_stock(branch: to_branch, quantity: arriving, reason: "transfer_in", source: self, creator: user, reverses: { taken_by: self }, pieces: line.offcut_lengths.presence) if arriving.positive?
        next unless line.short_quantity.positive?

        if self.shortfall == "lost"
          line.product.move_stock(branch: to_branch, quantity: -line.short_quantity, reason: "lost_in_transit", source: self, creator: user)
        else
          line.product.move_stock(branch: from_branch, quantity: line.short_quantity, reason: "transfer_returned", source: self, creator: user, reverses: { taken_by: self })
        end
      end
      update! status: :received, receiver: user, received_at: Time.current
      track_event "received", short: short_description.presence
    end
  end

  def short?
    lines.any? { _1.short_quantity.positive? }
  end

  # "2 Bamburi cement 50kg lost in transit", for the event and the notice.
  def short_description
    return "" unless short?

    what = lines.select { _1.short_quantity.positive? }.map { "#{_1.short_quantity.to_s("F").delete_suffix(".0")} #{_1.product.name}" }.to_sentence
    shortfall == "lost" ? "#{what} lost in transit" : "#{what} returned to #{from_branch.name}"
  end

  def cancel(user = Current.user)
    with_lock do
      return false unless in_transit?

      lines.each { |line| line.product.move_stock(branch: from_branch, quantity: line.quantity, reason: "transfer_returned", source: self, creator: user, reverses: { taken_by: self }, pieces: line.offcut_lengths.presence) }
      update! status: :cancelled
      track_event "cancelled"
    end
  end

  def name
    "##{id} #{from_branch.name} → #{to_branch.name}"
  end

  private
    def receipt_adds_up
      lines.each do |line|
        if line.received_quantity.negative?
          errors.add :base, "#{line.product.name} received can't be less than nothing"
        elsif line.received_quantity > line.quantity
          errors.add :base, "Only #{line.quantity.to_s("F").delete_suffix(".0")} #{line.product.name} were sent"
        elsif !line.product.quantity_allowed?(line.received_quantity)
          errors.add :base, "#{line.product.name} received must be a whole number"
        end
      end
      errors.add :base, "Say what happened to what's short: lost on the way, or still at #{from_branch.name}" if short? && !shortfall.in?(SHORTFALLS)
    end

    def send_stock
      lines.each do |line|
        # Offcuts that no longer fit in what's left have gone on the lorry: the line remembers them, to list where they arrive.
        before = line.product.cut_to_length? ? line.product.offcuts.where(branch: from_branch).pluck(:length) : []
        line.product.move_stock(branch: from_branch, quantity: -line.quantity, reason: "transfer_out", source: self, creator: sender)
        gone = before.any? ? before.tally.merge(line.product.offcuts.where(branch: from_branch).pluck(:length).tally) { |_, was, is| was - is }.flat_map { |length, count| [ length ] * count } : []
        line.update_columns(offcut_lengths: gone.sort) if gone.any?
      end
      track_event "sent"
    end
end
