class MaterialCalculator::Plaster < MaterialCalculator::Part
  WASTE = 1.10

  self.title = "Plastering"
  self.description = "Plaster or render on walls and ceilings"
  self.fields = [
    Field.new(name: "area", label: "Area (m²)", hint: "Both faces of a wall count"),
    Field.new(name: "thickness", label: "Thickness (mm)", default: 15),
    Field.new(name: "mix", label: "Mix", default: "4", options: [ [ "1 cement : 4 sand", "4" ], [ "1 cement : 6 sand", "6" ] ])
  ]
  self.required = %w[ area ]
  self.assumptions = "10% extra for droppings and uneven walls."

  def summary = "Plastering, #{measure(number("area"))} m² at #{measure(number("thickness") || 15)} mm"

  private
    def calculate
      MaterialCalculator.mortar(number("area") * (number("thickness") || 15) / 1000 * WASTE, sand: choice("mix").to_i)
    end
end
