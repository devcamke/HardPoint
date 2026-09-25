class GoodsReceiptLine < ApplicationRecord
  include AccountOwned, Monetary

  belongs_to :goods_receipt, inverse_of: :lines
  belongs_to :purchase_order_line, optional: true
  belongs_to :product

  attr_reader :product_code

  money_attribute :unit_cost, :landed_unit_cost

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_cost_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :product, :purchase_order_line
  validate { errors.add :base, "No product with barcode or SKU “#{product_code}”" if product_code.present? && product.nil? }
  validate { errors.add :base, "#{product.name} doesn't track stock" if product && !product.track_stock? }
  validate { errors.add :quantity, "of #{product.name} must be a whole number" if product && quantity && !product.quantity_allowed?(quantity) }
  validate :within_what_was_ordered
  validate { errors.add :base, "#{product.name} needs its batch number" if product&.tracks_batches? && batch_number.blank? }

  normalizes :batch_number, with: ->(number) { number.squish.upcase.presence }

  before_validation { self.product ||= purchase_order_line&.product }
  before_validation(if: -> { unit_cost_cents.nil? }) { self.unit_cost_cents = purchase_order_line&.unit_cost_cents || product&.cost_cents }

  def product_code=(code)
    @product_code = code
    self.product = Current.account.products.find_by_code(code) if code.present?
  end

  def batch
    { number: batch_number, expires_on: expires_on } if batch_number
  end

  def line_value_cents
    (unit_cost_cents.to_i * quantity.to_d).round
  end

  private
    # Extra goods not on the order go on a separate receipt, so the order stays a true record.
    def within_what_was_ordered
      return unless purchase_order_line && quantity

      if purchase_order_line.purchase_order_id != goods_receipt&.purchase_order_id
        errors.add :base, "That line isn't on this purchase order"
      elsif quantity > purchase_order_line.outstanding_quantity
        errors.add :base, "Only #{purchase_order_line.outstanding_quantity.to_s("F").delete_suffix(".0")} of #{product.name} still to come on this order"
      end
    end
end
