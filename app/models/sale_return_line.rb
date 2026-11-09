# One item (or so many of it) brought back on a return. The lines of a return are priced together
# (SaleReturnLine.price): a refund is what the customer paid for the goods before the return, less
# what the goods they keep are worth with the sale's promotions worked out again over what's left.
# So returning one pipe of "any 3 for 3,000" gives back 600, not a third of 3,000, because the two
# kept are no longer a bundle; and returning the free bag of "buy 10, get 1" gives back nothing.
class SaleReturnLine < ApplicationRecord
  include AccountOwned

  # A sale line as it would be with a different quantity, for asking a promotion what it would take off.
  Remaining = Data.define(:product, :quantity, :unit_price_cents, :product_unit)

  belongs_to :sale_return, inverse_of: :lines
  belongs_to :sale_line

  validates :quantity, numericality: { greater_than: 0 }
  validates_same_account :sale_line
  validate :from_the_same_sale, :not_more_than_bought, :whole_units

  # Sets total_cents and tax_cents on each of these return lines (all from one sale). Each sale line's
  # value is worked out at the quantity left before this return and after it; the difference is refunded.
  # Where a return breaks a bundle, the lines kept are worth more than was paid for them, and that
  # comes off the refund of the lines going back, shared in proportion. A cart discount is spread the
  # same way as it was on the sale. Nothing is ever refunded below zero.
  def self.price(return_lines, sale)
    # A line from another receipt fails validation; it isn't priced.
    return_lines = return_lines.select { _1.sale_line&.sale_id == sale.id && _1.quantity&.positive? }
    return if return_lines.empty?

    sale_lines = sale.lines.includes(:product, :product_unit, :promotion).to_a
    already = SaleReturnLine.joins(:sale_return).where(sale_returns: { sale_id: sale.id }).where.not(sale_return_id: return_lines.first.sale_return_id)
      .group(:sale_line_id).sum(:quantity)
    returning = return_lines.group_by(&:sale_line_id).transform_values { |lines| lines.sum(&:quantity) }

    before = sale_lines.to_h { [ _1.id, _1.quantity - already.fetch(_1.id, 0) ] }
    after = before.to_h { |id, left| [ id, [ left - returning.fetch(id, 0), 0 ].max ] }
    change = value_of(sale_lines, before).merge(value_of(sale_lines, after)) { |_, was, is| was - is }

    # Kept lines whose value went up (their bundle is broken) cost the lines going back their share.
    lost = -change.select { |id, _| returning[id].nil? }.values.sum
    refunded = change.select { |id, _| returning[id] }
    positive = refunded.values.select(&:positive?).sum
    cart_factor = sale.subtotal_cents.zero? ? 1 : sale.total_cents.to_r / sale.subtotal_cents

    return_lines.each do |line|
      share = line.quantity / returning[line.sale_line_id]
      delta = refunded[line.sale_line_id]
      delta -= lost * (positive.positive? ? delta.to_r / positive : 1.to_r / returning.size) if lost.positive?
      line.total_cents = [ (delta * share * cart_factor).round, 0 ].max
      line.tax_cents = (line.total_cents * line.sale_line.tax_rate / (100 + line.sale_line.tax_rate)).round
    end
  end

  # { sale line id => what those quantities of each line are worth }, with promotions worked out again
  # over them: line by line for percentages and free items, across the lines for a bundle. At the
  # quantities sold nothing is recomputed; the lines are worth what the receipt says they cost.
  def self.value_of(sale_lines, quantities)
    return sale_lines.to_h { [ _1.id, _1.total_cents ] } if sale_lines.all? { quantities[_1.id] == _1.quantity }

    bundled = sale_lines.select { _1.promotion&.bundle? }.group_by(&:promotion).flat_map do |promotion, lines|
      remaining = lines.to_h { [ Remaining.new(_1.product, quantities[_1.id], _1.unit_price_cents, _1.product_unit), _1.id ] }
      promotion.bundle_savings(remaining.keys.select { _1.quantity.positive? }).map { |stand_in, cents| [ remaining[stand_in], cents ] }
    end.to_h

    sale_lines.to_h do |line|
      left = quantities[line.id]
      saving = if line.promotion.nil? then 0
      elsif line.promotion.bundle? then bundled.fetch(line.id, 0)
      else line.promotion.saving_cents(product: line.product, quantity: left, unit_price_cents: line.unit_price_cents, product_unit: line.product_unit)
      end
      [ line.id, (line.unit_price_cents * left).round - (line.discount_cents * left / line.quantity).round - saving ]
    end
  end

  private
    def from_the_same_sale
      errors.add :sale_line, "isn't on this receipt" if sale_line && sale_return && sale_line.sale_id != sale_return.sale_id
    end

    def not_more_than_bought
      return unless sale_line && quantity

      returnable = sale_line.quantity - sale_line.sale.returned_quantity(sale_line)
      errors.add :base, "Only #{returnable.to_s("F").delete_suffix(".0")} of #{sale_line.product.name} can still be returned" if quantity > returnable
    end

    def whole_units
      errors.add :quantity, "must be a whole number" if sale_line && quantity && !sale_line.product_unit && !sale_line.product.quantity_allowed?(quantity)
    end
end
