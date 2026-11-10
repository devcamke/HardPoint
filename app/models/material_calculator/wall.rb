class MaterialCalculator::Wall < MaterialCalculator::Part
  # [ length, height, thickness ] in metres, and the joint between them.
  UNITS = { "stone_9x9" => [ 0.45, 0.225, 0.225, 0.012 ], "stone_6x9" => [ 0.45, 0.225, 0.15, 0.012 ],
            "block_6in" => [ 0.40, 0.20, 0.15, 0.010 ], "block_4in" => [ 0.40, 0.20, 0.10, 0.010 ] }.freeze
  WASTE = 1.05

  self.title = "Wall"
  self.description = "Stone or block walling, and the mortar to lay it"
  self.fields = [
    Field.new(name: "length", label: "Length (m)", hint: "All the walls together"),
    Field.new(name: "height", label: "Height (m)"),
    Field.new(name: "openings", label: "Doors and windows (m²)", default: 0, hint: "Left out of the wall"),
    Field.new(name: "unit", label: "Built with", default: "stone_9x9",
      options: UNITS.keys.map { [ MaterialCalculator.material(_1).name, _1 ] }),
    Field.new(name: "mix", label: "Mortar", default: "4", options: [ [ "1 cement : 4 sand", "4" ], [ "1 cement : 6 sand", "6" ] ])
  ]
  self.required = %w[ length height ]
  self.assumptions = "Joints of 10–12 mm, 5% extra stones or blocks for breakages and cuts, and mortar worked out from the gaps between them."

  def summary = "Wall, #{measure(number("length"))} m × #{measure(number("height"))} m"

  private
    def calculate
      length, height, thickness, joint = UNITS.fetch(choice("unit")).map(&:to_d)
      area = [ number("length") * number("height") - (number("openings") || 0), 0 ].max
      units = area / ((length + joint) * (height + joint))
      mortar = (area * thickness - units * length * height * thickness) * WASTE
      { choice("unit") => (units * WASTE).ceil }.merge(MaterialCalculator.mortar(mortar, sand: choice("mix").to_i))
    end
end
