# Turns the parts of a building job (a wall, a slab, plastering, a roof, tiling, painting) into the materials it needs,
# in the units Kenyan hardware shops sell them by, with an allowance for waste. Each shop says once which of its
# products is each material (MaterialProduct); an estimate then becomes a quote at today's prices.
#
# The figures are a counter's estimate, not an engineer's: the assumptions behind each are shown beside it.
module MaterialCalculator
  # unit is one of it ("tonne"), units several ("tonnes").
  Material = Data.define(:key, :name, :unit, :units)

  MATERIALS = [
    Material.new("cement", "Cement", "bag of 50 kg", "bags of 50 kg"),
    Material.new("sand", "Sand", "tonne", "tonnes"),
    Material.new("ballast", "Ballast", "tonne", "tonnes"),
    Material.new("stone_9x9", "Machine-cut stone 9×9", "piece", "pieces"),
    Material.new("stone_6x9", "Machine-cut stone 6×9", "piece", "pieces"),
    Material.new("block_6in", "Concrete block 6 inch", "piece", "pieces"),
    Material.new("block_4in", "Concrete block 4 inch", "piece", "pieces"),
    Material.new("bar_y8", "Y8 bar", "12 m length", "12 m lengths"),
    Material.new("bar_y10", "Y10 bar", "12 m length", "12 m lengths"),
    Material.new("bar_y12", "Y12 bar", "12 m length", "12 m lengths"),
    Material.new("bar_y16", "Y16 bar", "12 m length", "12 m lengths"),
    Material.new("brc_a142", "BRC mesh A142", "sheet of 2.4 × 4.8 m", "sheets of 2.4 × 4.8 m"),
    Material.new("binding_wire", "Binding wire", "kg", "kg"),
    Material.new("iron_sheet", "Iron sheet", "sheet", "sheets"),
    Material.new("ridge_cap", "Ridge cap", "piece", "pieces"),
    Material.new("roofing_nails", "Roofing nails", "kg", "kg"),
    Material.new("tiles", "Tiles", "m²", "m²"),
    Material.new("tile_adhesive", "Tile adhesive", "bag of 20 kg", "bags of 20 kg"),
    Material.new("tile_grout", "Tile grout", "kg", "kg"),
    Material.new("paint", "Paint", "litre", "litres")
  ].index_by(&:key).freeze

  # Bulk densities and the cement bag, for turning volumes into what's sold.
  CEMENT_KG_PER_M3 = 1440
  CEMENT_BAG_KG = 50
  SAND_TONNES_PER_M3 = 1.6
  BALLAST_TONNES_PER_M3 = 1.5
  # Mortar and concrete shrink as they're mixed wet: the dry materials take up more room than the result.
  MORTAR_DRY_FACTOR = 1.33
  CONCRETE_DRY_FACTOR = 1.54
  STEEL_KG_PER_M = { "bar_y8" => 0.395, "bar_y10" => 0.617, "bar_y12" => 0.888, "bar_y16" => 1.58 }.freeze
  BAR_LENGTH_M = 12

  KINDS = %w[ wall concrete plaster roof tiles paint ].freeze

  def self.material(key) = MATERIALS.fetch(key)

  def self.part_class(kind)
    "MaterialCalculator::#{kind.to_s.camelize}".constantize if kind.to_s.in?(KINDS)
  end

  # Cement and sand for mortar or plaster of this wet volume, at 1 part cement to `sand` parts sand.
  def self.mortar(wet_m3, sand: 4)
    dry = wet_m3 * MORTAR_DRY_FACTOR
    { "cement" => dry / (1 + sand) * CEMENT_KG_PER_M3 / CEMENT_BAG_KG, "sand" => dry * sand / (1 + sand) * SAND_TONNES_PER_M3 }
  end

  # Numbers typed into the form: blank or nonsense is nil, so a part with nothing filled in is left out.
  def self.number(value)
    decimal = BigDecimal(value.to_s.delete(", "), exception: false)
    decimal if decimal&.positive?
  end
end
