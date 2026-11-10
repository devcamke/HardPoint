module MaterialCalculatorHelper
  # "131", "18.4", "0.5": a material's quantity as a counter would say it, to a tenth below ten.
  def material_quantity(quantity)
    decimal = quantity.to_d
    rounded = decimal.round(decimal < 10 ? 1 : 0).to_d
    number_with_delimiter(rounded.frac.zero? ? rounded.to_i : rounded.to_s("F"))
  end
end
