# A unit of measure: piece, box, kilogram, metre… Fractional units (kg, m, litre) allow
# quantities like 2.5; the others only whole numbers.
class Unit < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  has_many :products, dependent: :restrict_with_error
  has_many :product_units, dependent: :restrict_with_error

  validates :name, :abbreviation, presence: true
  validates :name, uniqueness: { scope: :account_id }
  normalizes :etims_code, with: ->(code) { code.strip.upcase.presence }

  scope :alphabetically, -> { order(:name) }

  # How many of this unit make a kilogram, for units a scale can fill in at the till; nil for the rest.
  PER_KILOGRAM = { "kg" => 1, "kilogram" => 1, "kilograms" => 1, "g" => 1000, "gram" => 1000, "grams" => 1000 }.freeze

  def per_kilogram
    PER_KILOGRAM[abbreviation.to_s.downcase.strip] || PER_KILOGRAM[name.to_s.downcase.strip] if fractional?
  end

  def valid_quantity?(quantity)
    fractional? || quantity.to_d.frac.zero?
  end
end
