# A goods received note (GRN). Recording one puts the goods into stock at the branch, spreads
# any extra costs (transport, duty) over the lines by value, updates each product's weighted-average
# cost, and marks the purchase order (if any) partially or fully received.
class GoodsReceipt < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :purchase_order, optional: true
  belongs_to :branch
  belongs_to :receiver, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, class_name: "GoodsReceiptLine", dependent: :destroy, inverse_of: :goods_receipt
  has_many :supplier_invoices, dependent: :nullify

  money_attribute :extra_costs, :total

  accepts_nested_attributes_for :lines,
    reject_if: ->(attributes) { attributes["quantity"].to_s.strip.in?([ "", "0" ]) && attributes["product_code"].blank? }

  validates :extra_costs_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :supplier, :purchase_order, :branch
  validate { errors.add :base, "Add at least one item received" if lines.empty? }
  validate :matches_purchase_order

  before_create :number_and_cost
  after_create :put_into_stock

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }

  def reference
    "#{branch.code}-GRN#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  def goods_value_cents
    lines.sum(&:line_value_cents)
  end

  private
    def matches_purchase_order
      return unless purchase_order

      errors.add :purchase_order, "is for another supplier" if purchase_order.supplier_id != supplier_id
      errors.add :purchase_order, "is for another branch" if purchase_order.branch_id != branch_id
      errors.add :purchase_order, "is #{purchase_order.status.humanize.downcase}, so nothing more can be received" unless purchase_order.receivable?
    end

    # Extra costs are shared by value; if everything came free, by quantity.
    def number_and_cost
      self.number = DocumentSequence.next_number(branch, "goods_receipt")
      value = goods_value_cents
      units = lines.sum(&:quantity)

      lines.each do |line|
        share = value.positive? ? line.line_value_cents.to_r / value : line.quantity / units
        line.landed_unit_cost_cents = line.unit_cost_cents + (extra_costs_cents * share / line.quantity).round
      end
      self.total_cents = value + extra_costs_cents
    end

    def put_into_stock
      lines.each do |line|
        line.product.receive_into_stock(branch: branch, quantity: line.quantity, unit_cost_cents: line.landed_unit_cost_cents, source: self, batch: line.batch)
        line.purchase_order_line&.increment!(:received_quantity, line.quantity)
        remember_supplier_cost(line)
      end

      purchase_order&.refresh_receipt_status
      track_event "received", supplier: supplier.name, total: total_cents, purchase_order: purchase_order&.reference
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
