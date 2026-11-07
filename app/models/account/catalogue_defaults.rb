# What a new shop starts with, so it can add products straight away. All of it can be edited.
module Account::CatalogueDefaults
  extend ActiveSupport::Concern

  DEFAULT_UNITS = [
    [ "Piece", "pc", false ], [ "Box", "box", false ], [ "Pack", "pk", false ], [ "Pair", "pr", false ],
    [ "Set", "set", false ], [ "Bag", "bag", false ], [ "Roll", "roll", false ], [ "Sheet", "sht", false ],
    [ "Length", "len", false ], [ "Tin", "tin", false ], [ "Kilogram", "kg", true ], [ "Metre", "m", true ],
    [ "Foot", "ft", true ], [ "Litre", "l", true ]
  ].freeze

  # Kenya's standard VAT rates, matching the default currency; shops elsewhere change them.
  DEFAULT_TAX_RATES = [ [ "Standard VAT", 16, true ], [ "Zero-rated", 0, false ], [ "Exempt", 0, false ] ].freeze
  DEFAULT_PRICE_LISTS = %w[ Contractor Wholesale ].freeze

  def create_catalogue_defaults
    DEFAULT_UNITS.each { |name, abbreviation, fractional| units.create!(name: name, abbreviation: abbreviation, fractional: fractional) }
    DEFAULT_TAX_RATES.each { |name, rate, default| tax_rates.create!(name: name, rate: rate, default: default) }
    DEFAULT_PRICE_LISTS.each { |name| price_lists.create!(name: name) }
  end

  def default_unit
    units.find_by(name: "Piece") || units.alphabetically.first
  end

  def default_tax_rate
    tax_rates.find_by(default: true)
  end
end
