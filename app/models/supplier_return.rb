# Goods sent back to a supplier: damaged on arrival, the wrong item, not what was ordered, faulty.
# Recording the return takes the goods out of stock at the branch and raises a debit note for what
# they cost (with VAT), which comes straight off what the shop owes the supplier and off the input
# VAT for the period. When the supplier's credit note arrives, its number is noted against it.
class SupplierReturn < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  REASONS = %w[ damaged wrong_item not_ordered faulty expired other ].freeze

  belongs_to :supplier
  belongs_to :branch
  belongs_to :goods_receipt, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, -> { order(:id) }, class_name: "SupplierReturnLine", dependent: :destroy, inverse_of: :supplier_return

  money_attribute :total, :tax

  accepts_nested_attributes_for :lines, reject_if: ->(attributes) { attributes["quantity"].to_s.strip.in?([ "", "0" ]) }

  validates :reason, inclusion: { in: REASONS }
  validates_same_account :supplier, :branch, :goods_receipt
  validate { errors.add :base, "Add at least one item going back" if lines.empty? }
  validate { errors.add :goods_receipt, "is from another supplier or branch" if goods_receipt && (goods_receipt.supplier_id != supplier_id || goods_receipt.branch_id != branch_id) }
  validate { errors.add :base, "#{lines.map(&:product).compact.tally.select { _2 > 1 }.keys.map(&:name).to_sentence} is listed twice" if lines.map(&:product).compact.tally.any? { _2 > 1 } }

  before_validation(on: :create) { self.exchange_rate ||= goods_receipt&.exchange_rate || supplier&.current_rate if supplier&.foreign? }
  before_create :number_and_totals
  after_create :take_out_of_stock

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :awaiting_credit, -> { where(credit_note_number: nil) }

  def reference
    "#{branch.code}-SR#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  # Costs, totals and the debit note are in the supplier's currency.
  def currency = supplier.currency_code

  def credited? = credit_note_number.present?

  def to_base_cents(cents)
    exchange_rate ? (cents * exchange_rate.to_d).round : cents
  end

  def record_credit_note(number:, on: Date.current)
    if number.to_s.squish.blank?
      errors.add :credit_note_number, "can't be blank"
      return false
    end

    update(credit_note_number: number.to_s.squish, credited_on: on).tap do |saved|
      track_event "credited", credit_note_number: credit_note_number, total: total_cents if saved
    end
  end

  private
    def number_and_totals
      self.number = DocumentSequence.next_number(branch, "supplier_return")
      lines.each(&:calculate_totals)
      self.total_cents = lines.sum(&:total_cents)
      self.tax_cents = lines.sum(&:tax_cents)
    end

    def take_out_of_stock
      lines.each do |line|
        line.product.move_stock(branch: branch, quantity: -line.quantity, reason: "returned_to_supplier", source: self, batch: line.stock_batch,
          unit_cost_cents: to_base_cents(line.unit_cost_cents), note: reason.humanize, creator: creator)
      end
      track_event "created", supplier: supplier.name, total: total_cents, reason: reason, goods_receipt: goods_receipt&.reference
    end
end
