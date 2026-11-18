# A goods received note (GRN). Recording one puts the goods into stock at the branch, spreads
# any extra costs (transport, duty) over the lines by value, updates each product's weighted-average
# cost, and marks the purchase order (if any) partially or fully received.
#
# An order over the shop's limit was approved when it was sent (PurchaseOrder), and a receipt can't bring in more
# than its order has outstanding. What no order covers is where one person could still buy alone: goods received
# with no order, or at a dearer cost than was ordered. Once that comes to more than the same limit for one person
# in a day, the receipt needs an owner or manager too. Receipts made from a supplier's invoice at KRA
# (Etims::Purchase) aren't counted: the invoice is the supplier's own record of the sale.
class GoodsReceipt < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :purchase_order, optional: true
  belongs_to :branch
  belongs_to :receiver, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, class_name: "GoodsReceiptLine", dependent: :destroy, inverse_of: :goods_receipt
  has_many :supplier_invoices, dependent: :nullify
  has_many :etims_purchases, class_name: "Etims::Purchase", dependent: :nullify

  money_attribute :extra_costs, :total

  # Who approved it, when it needed approving: kept on its Activity entry.
  attr_accessor :approver

  accepts_nested_attributes_for :lines,
    reject_if: ->(attributes) { attributes["quantity"].to_s.strip.in?([ "", "0" ]) && attributes["product_code"].blank? }

  validates :extra_costs_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :supplier, :purchase_order, :branch
  validate { errors.add :base, "Add at least one item received" if lines.empty? }
  validate :matches_purchase_order

  before_validation(on: :create) { self.exchange_rate ||= supplier&.current_rate if supplier&.foreign? }
  validate { errors.add :exchange_rate, "is needed for #{supplier.name}'s #{supplier.currency}" if supplier&.foreign? && !exchange_rate.to_d.positive? }

  before_create :number_and_cost
  after_create :put_into_stock

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def reference
    "#{branch.code}-GRN#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  # Unit costs are as on the supplier's invoice, in their currency; stock and totals are in the shop's.
  def currency = supplier.currency_code

  def goods_value_cents
    lines.sum(&:line_value_cents)
  end

  def to_base(cents)
    exchange_rate ? cents * exchange_rate.to_d : cents
  end

  def goods_value_base_cents
    lines.sum { to_base(_1.line_value_cents) }.round
  end

  # What this brings in that no order covers, in the shop's money: lines on no order in full, and on an order's
  # lines whatever the cost is above the cost ordered. Read once the receipt has been checked (the lines are in
  # the product's own unit by then).
  def unordered_value_cents
    lines.sum do |line|
      ordered = line.purchase_order_line
      to_base(ordered ? [ line.unit_cost_cents.to_i - ordered.unit_cost_cents, 0 ].max * line.quantity.to_d : line.line_value_cents)
    end.round
  end

  # What the receiver has already brought in today (the shop's day) that no order covers.
  def unordered_earlier_today_cents
    @unordered_earlier_today_cents ||= begin
      midnight = Time.use_zone(account.time_zone) { Time.zone.now.beginning_of_day }
      account.goods_receipts.where(receiver: receiver, created_at: midnight..).where.not(id: id).where.missing(:etims_purchases)
        .includes(lines: :purchase_order_line).sum(&:unordered_value_cents)
    end
  end

  def needs_approval?
    unordered_value_cents.positive? && unordered_value_cents + unordered_earlier_today_cents > account.purchase_approval_above_cents
  end

  def approval_needed_message
    so_far = " (#{Money.format(unordered_earlier_today_cents)} already today)" if unordered_earlier_today_cents.positive?
    "#{Money.format(unordered_value_cents)} of this isn't covered by an order#{so_far}. Receiving more than " \
      "#{Money.format(account.purchase_approval_above_cents)} in a day without one, or dearer than ordered, needs a manager's approval PIN"
  end

  private
    def matches_purchase_order
      return unless purchase_order

      errors.add :purchase_order, "is for another supplier" if purchase_order.supplier_id != supplier_id
      errors.add :purchase_order, "is for another branch" if purchase_order.branch_id != branch_id
      errors.add :purchase_order, "is #{purchase_order.status.humanize.downcase}, so nothing more can be received" unless purchase_order.receivable?
    end

    # Extra costs are shared by value; if everything came free, by quantity.
    # Goods from a supplier in another currency are converted at this receipt's rate; transport and
    # duty are paid here, in the shop's currency.
    def number_and_cost
      self.number = DocumentSequence.next_number(branch, "goods_receipt")
      value = goods_value_cents
      units = lines.sum(&:quantity)

      lines.each do |line|
        share = value.positive? ? line.line_value_cents.to_r / value : line.quantity / units
        line.landed_unit_cost_cents = (to_base(line.unit_cost_cents) + extra_costs_cents * share / line.quantity).round
      end
      self.total_cents = goods_value_base_cents + extra_costs_cents
    end

    def put_into_stock
      lines.each do |line|
        line.product.receive_into_stock(branch: branch, quantity: line.quantity, unit_cost_cents: line.landed_unit_cost_cents, source: self, batch: line.batch)
        line.purchase_order_line&.increment!(:received_quantity, line.quantity)
        remember_supplier_cost(line)
      end

      purchase_order&.refresh_receipt_status
      track_event "received", supplier: supplier.name, total: total_cents, purchase_order: purchase_order&.reference,
        approver: approver, unordered: (unordered_value_cents if approver)
    end

    # The supplier's latest price, used for the next order.
    def remember_supplier_cost(line)
      supplier.supplier_products.find_or_initialize_by(product: line.product).tap do |supplier_product|
        supplier_product.account = account
        supplier_product.cost_cents = line.unit_cost_cents
        supplier_product.save!
      end
    end
end
