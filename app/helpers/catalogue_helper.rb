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

  # Pass the branch's reorder level when the list already has its stock levels, to save a query a row.
  def stock_badge(product, stock, branch, reorder_level: nil)
    if !product.track_stock? && !product.kit?
      status_dot "Not tracked", :muted
    elsif stock <= 0
      status_dot "Out", :danger
    elsif (reorder_level ||= product.reorder_level_at(branch)).positive? && stock <= reorder_level
      status_dot "Low", :warning
    end
  end

  def movement_reason(reason)
    reason.humanize
  end
end
