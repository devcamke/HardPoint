# A quantity of one sale line going out on a delivery note. A sale can go out over several notes, so a
# line can't carry more than the sale sold less what earlier notes (not cancelled) already carried.
class DeliveryNoteLine < ApplicationRecord
  include AccountOwned

  belongs_to :delivery_note, inverse_of: :lines
  belongs_to :sale_line

  validates :quantity, numericality: { greater_than: 0 }
  validates_same_account :sale_line
  validate :from_the_same_sale, :not_more_than_undelivered

  delegate :product, :description, :unit, to: :sale_line

  private
    def from_the_same_sale
      errors.add :sale_line, "isn't on this sale" if sale_line && delivery_note && sale_line.sale_id != delivery_note.sale_id
    end

    def not_more_than_undelivered
      return unless sale_line && quantity && delivery_note&.sale

      left = DeliveryNote.undelivered_by_line(delivery_note.sale, except: delivery_note).fetch(sale_line.id, 0)
      errors.add :base, "Only #{left.to_s("F").delete_suffix(".0")} of #{sale_line.description} is still to be delivered" if quantity > left
    end
end
