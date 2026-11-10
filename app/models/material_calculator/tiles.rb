class MaterialCalculator::Tiles < MaterialCalculator::Part
  WASTE = 1.10
  ADHESIVE_KG_PER_M2 = 5
  GROUT_KG_PER_M2 = 0.5

  self.title = "Tiling"
  self.description = "Floor or wall tiles, adhesive and grout"
  self.fields = [ Field.new(name: "area", label: "Area (m²)") ]
  self.required = %w[ area ]
  self.assumptions = "10% extra tiles for cuts and breakages; adhesive at about 5 kg and grout at 0.5 kg per m²."

  def summary = "Tiling, #{measure(number("area"))} m²"

  private
    def calculate
      area = number("area") * WASTE
      { "tiles" => area, "tile_adhesive" => (area * ADHESIVE_KG_PER_M2 / 20).ceil, "tile_grout" => (area * GROUT_KG_PER_M2).ceil }
    end
end
