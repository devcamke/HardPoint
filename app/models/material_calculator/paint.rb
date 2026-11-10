class MaterialCalculator::Paint < MaterialCalculator::Part
  WASTE = 1.10

  self.title = "Painting"
  self.description = "Emulsion or gloss for walls and ceilings"
  self.fields = [
    Field.new(name: "area", label: "Area (m²)"),
    Field.new(name: "coats", label: "Coats", default: 2),
    Field.new(name: "coverage", label: "Covers (m² per litre)", default: 10, hint: "On the tin; about 10 for emulsion")
  ]
  self.required = %w[ area ]
  self.assumptions = "10% extra for the first coat soaking into new plaster."

  def summary = "Painting, #{measure(number("area"))} m², #{(number("coats") || 2).ceil} coats"

  private
    def calculate
      { "paint" => number("area") * (number("coats") || 2).ceil / (number("coverage") || 10) * WASTE }
    end
end
