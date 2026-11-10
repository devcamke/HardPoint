# A purchase order or goods receipt line that can be entered by the pack: "3 boxes" of a product that
# comes 100 to the box. The pack typed on the form is one of the product's pack sizes, named by its
# unit ("box" or "Box"); the quantity and unit cost typed alongside it are per pack, and are turned into
# the product's own unit when the line is checked, since stock and costs are kept in that. The pack and
# how many of it stay on the line for the form, the page and the PDF. A line typed without a pack is in
# the product's unit, as before.
module BoughtByThePack
  extend ActiveSupport::Concern

  included do
    belongs_to :product_unit, optional: true

    attr_reader :pack

    validates_same_account :product_unit
    validate { errors.add :base, "#{pack_product.name} has no pack called “#{pack}”" if pack.present? && pack_product && product_unit.nil? }
    validates :pack_quantity, numericality: { greater_than: 0 }, allow_nil: true

    before_validation :convert_packs, if: -> { @pack_given }
  end

  # The pack isn't a column, so on a saved line it marks the line changed itself: otherwise a form that
  # changed only the pack would be skipped when the order saves its lines.
  def pack=(name)
    @pack = name.to_s.strip
    @pack_given = true
    pack_quantity_will_change! if persisted?
  end

  # The product whose pack sizes the pack is one of. A receipt line against an order may not have its
  # product filled in yet, so it looks to the order line.
  def pack_product
    product
  end

  # What was typed, or what the line was saved with: the pack's unit name, or blank for the product's unit.
  def pack_name
    @pack_given ? pack : product_unit&.unit&.name&.downcase
  end

  # The quantity as it reads on the form: packs if the line has a pack, else the product's unit.
  def entered_quantity
    product_unit ? pack_quantity : quantity
  end

  # The unit cost as it reads on the form and the order: per pack if the line has one.
  def pack_unit_cost_cents
    product_unit ? (unit_cost_cents.to_i * product_unit.quantity).round : unit_cost_cents
  end

  # "3 box" for a line bought by the pack, nil otherwise.
  def packs_description
    "#{pack_quantity.to_s("F").delete_suffix(".0")} #{product_unit.unit.abbreviation}" if product_unit && pack_quantity
  end

  private
    def convert_packs
      if pack.blank?
        self.product_unit = nil
        self.pack_quantity = nil
        return
      end

      self.product_unit = pack_product&.product_units&.joins(:unit)&.find_by("lower(units.name) = :pack OR lower(units.abbreviation) = :pack", pack: pack.downcase)
      return unless product_unit && quantity

      self.pack_quantity = quantity
      self.quantity = pack_quantity * product_unit.quantity
      self.unit_cost_cents = (unit_cost_cents / product_unit.quantity).round if unit_cost_cents.to_i.positive?
    end
end
