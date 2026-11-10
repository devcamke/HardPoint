# A job as its parts, and what they come to: each material totalled over the parts, then as the shop's own product
# (a whole number of anything sold whole, rounded up) at today's shelf price.
class MaterialCalculator::Estimate
  Line = Data.define(:material, :quantity, :product, :product_unit, :sell_quantity) do
    def mapped? = product.present?
    def unit_price_cents = product_unit ? product_unit.effective_price_cents : product.price_cents
    def total_cents = (unit_price_cents * sell_quantity).round
  end

  attr_reader :account, :parts

  # parts: [ { "kind" => "wall", "length" => "12", … }, … ] as the form sends them.
  def initialize(account, parts)
    @account = account
    @parts = Array(parts).filter_map { |values| MaterialCalculator.part_class(values["kind"] || values[:kind])&.new(values) }
  end

  def filled_parts = parts.select(&:filled?)

  def materials
    @materials ||= filled_parts.each_with_object(Hash.new(0)) { |part, totals| part.materials.each { totals[_1] += _2.to_d } }
  end

  def lines
    @lines ||= begin
      mapped = account.material_products.includes(product: :unit, product_unit: :unit).index_by(&:material)
      MaterialCalculator::MATERIALS.keys.filter_map do |key|
        next unless (quantity = materials[key]).positive?

        mapping = mapped[key]
        Line.new(MaterialCalculator.material(key), quantity, mapping&.product, mapping&.product_unit, mapping ? mapping.sell_quantity(quantity) : nil)
      end
    end
  end

  def total_cents = lines.select(&:mapped?).sum(&:total_cents)

  def unmapped = lines.reject(&:mapped?)

  # A quote for the customer with one line per material the shop sells, noting the parts it was worked out from.
  def to_quote(customer:, branch:)
    account.customer_orders.new(customer: customer, branch: branch, status: :quote,
      note: "Worked out for: #{filled_parts.map(&:summary).join("; ")}".truncate(250),
      lines_attributes: lines.select(&:mapped?).map { { product: _1.product, product_unit: _1.product_unit, quantity: _1.sell_quantity } })
  end
end
