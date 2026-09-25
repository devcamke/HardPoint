module CatalogueHelper
  def money(cents, currency: Current.account&.currency)
    return "—" if cents.nil?

    number_to_currency(cents / 100.0, unit: "#{currency} ", precision: Currency.decimals(currency), format: "%u%n", negative_format: "-%u%n")
  end

  # 25.500 → "25.5", 1000.0 → "1,000"
  def quantity(amount, unit = nil)
    formatted = number_with_precision(amount || 0, precision: 3, strip_insignificant_zeros: true, delimiter: ",")
    unit ? "#{formatted} #{unit.abbreviation}" : formatted
  end

  # For number fields: 12.0 → "12", 0.25 → "0.25", nil → nil.
  def plain_number(decimal)
    decimal&.to_d&.to_s("F")&.delete_suffix(".0")
  end

  def stock_badge(product, stock, branch)
    if !product.track_stock? && !product.kit?
      tag.span "Not tracked", class: "badge bg-concrete-200 text-steel-600"
    elsif stock <= 0
      tag.span "Out", class: "badge bg-red-50 text-red-800"
    elsif product.reorder_level.positive? && stock <= product.reorder_level
      tag.span "Low", class: "badge bg-safety-100 text-safety-800"
    end
  end

  def movement_reason(reason)
    reason.humanize
  end
end
