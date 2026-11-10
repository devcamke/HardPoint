class MaterialCalculator::Concrete < MaterialCalculator::Part
  MIXES = { "1:2:4" => [ 1, 2, 4 ], "1:1.5:3" => [ 1, 1.5, 3 ], "1:3:6" => [ 1, 3, 6 ] }.freeze
  WASTE = 1.05
  LAPS = 1.10

  self.title = "Concrete"
  self.description = "A slab, footing or beam: cement, sand, ballast and the steel in it"
  self.fields = [
    Field.new(name: "length", label: "Length (m)"),
    Field.new(name: "width", label: "Width (m)"),
    Field.new(name: "thickness", label: "Thickness (m)", default: "0.15", hint: "150 mm is 0.15"),
    Field.new(name: "count", label: "How many", default: 1, hint: "Footings or columns of the same size"),
    Field.new(name: "mix", label: "Mix", default: "1:2:4",
      options: [ [ "1:2:4 (slabs, beams)", "1:2:4" ], [ "1:1.5:3 (stronger)", "1:1.5:3" ], [ "1:3:6 (blinding)", "1:3:6" ] ]),
    Field.new(name: "steel", label: "Steel", default: "none",
      options: [ [ "None", "none" ], [ "BRC mesh A142", "brc_a142" ], [ "Y8 bars", "bar_y8" ], [ "Y10 bars", "bar_y10" ], [ "Y12 bars", "bar_y12" ], [ "Y16 bars", "bar_y16" ] ]),
    Field.new(name: "spacing", label: "Bar spacing (mm)", default: 200, hint: "Both ways, for bars")
  ]
  self.required = %w[ length width thickness ]
  self.assumptions = "Dry materials 1.54 times the concrete's volume and 5% waste; bars both ways with 10% for laps; mesh with 10% for overlaps; binding wire at 1 kg per 100 kg of steel."

  def summary = "Concrete, #{measure(number("length"))} × #{measure(number("width"))} × #{measure(number("thickness"))} m#{" × #{count}" if count > 1} (#{choice("mix")})"

  private
    def count = (number("count") || 1).ceil

    def calculate
      length, width = number("length"), number("width")
      dry = length * width * number("thickness") * count * MaterialCalculator::CONCRETE_DRY_FACTOR * WASTE
      cement, sand, ballast = MIXES.fetch(choice("mix")).map(&:to_d)
      parts = cement + sand + ballast
      materials = {
        "cement" => dry * cement / parts * MaterialCalculator::CEMENT_KG_PER_M3 / MaterialCalculator::CEMENT_BAG_KG,
        "sand" => dry * sand / parts * MaterialCalculator::SAND_TONNES_PER_M3,
        "ballast" => dry * ballast / parts * MaterialCalculator::BALLAST_TONNES_PER_M3
      }
      materials.merge(steel(length, width))
    end

    def steel(length, width)
      case (kind = choice("steel"))
      when "none" then {}
      when "brc_a142" then { "brc_a142" => (length * width * count * LAPS / (2.4 * 4.8).to_d).ceil }
      else
        spacing = (number("spacing") || 200) / 1000
        metres = (((width / spacing).floor + 1) * length + ((length / spacing).floor + 1) * width) * count * LAPS
        kilos = metres * MaterialCalculator::STEEL_KG_PER_M.fetch(kind).to_d
        { kind => (metres / MaterialCalculator::BAR_LENGTH_M).ceil, "binding_wire" => [ (kilos / 100).ceil, 1 ].max }
      end
    end
end
