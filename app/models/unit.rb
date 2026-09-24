# A unit of measure: piece, box, kilogram, metre… Fractional units (kg, m, litre) allow
# quantities like 2.5; the others only whole numbers.
class Unit < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  has_many :products, dependent: :restrict_with_error
  has_many :product_units, dependent: :restrict_with_error

  validates :name, :abbreviation, presence: true
  validates :name, uniqueness: { scope: :account_id }

  scope :alphabetically, -> { order(:name) }

  def valid_quantity?(quantity)
    fractional? || quantity.to_d.frac.zero?
  end
end
