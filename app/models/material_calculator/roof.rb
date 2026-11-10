class MaterialCalculator::Roof < MaterialCalculator::Part
  END_LAP = 0.15
  RIDGE_COVER = 1.8
  SHEETS_PER_KG_OF_NAILS = 10

  self.title = "Roofing"
  self.description = "Iron sheets, ridge caps and roofing nails"
  self.fields = [
    Field.new(name: "length", label: "Roof length (m)", hint: "Along the ridge, with the overhangs"),
    Field.new(name: "slope", label: "Eave to ridge (m)", hint: "Along the slope, with the overhang"),
    Field.new(name: "slopes", label: "Sides", default: "2", options: [ [ "Two sides (gable)", "2" ], [ "One side (lean-to)", "1" ] ]),
    Field.new(name: "sheet_length", label: "Sheet length (m)", default: "3", options: [ [ "2 m", "2" ], [ "2.5 m", "2.5" ], [ "3 m", "3" ] ]),
    Field.new(name: "cover", label: "Sheet cover width (m)", default: "0.76", hint: "0.76 for box profile, 0.686 for corrugated")
  ]
  self.required = %w[ length slope ]
  self.assumptions = "Sheets overlap 15 cm end to end; ridge caps cover 1.8 m each; about 1 kg of roofing nails for every 10 sheets."

  def summary = "Roof, #{measure(number("length"))} m long, #{measure(number("slope"))} m eave to ridge, #{choice("slopes") == "2" ? "two sides" : "one side"}"

  private
    def calculate
      sheet = choice("sheet_length").to_d
      across = (number("length") / (number("cover") || 0.76.to_d)).ceil
      up = number("slope") <= sheet ? 1 : 1 + ((number("slope") - sheet) / (sheet - END_LAP)).ceil
      sheets = across * up * choice("slopes").to_i
      { "iron_sheet" => sheets, "roofing_nails" => (sheets.to_d / SHEETS_PER_KG_OF_NAILS).ceil,
        "ridge_cap" => choice("slopes") == "2" ? (number("length") / RIDGE_COVER).ceil : 0 }
    end
end
