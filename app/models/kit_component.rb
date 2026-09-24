# A kit ("Plumbing starter kit") is sold as one product but made of others; selling it
# takes its components out of stock.
class KitComponent < ApplicationRecord
  include AccountOwned

  belongs_to :kit, class_name: "Product", inverse_of: :kit_components
  belongs_to :component, class_name: "Product"

  validates :quantity, numericality: { greater_than: 0 }
  validates :component, uniqueness: { scope: :kit_id, message: "is already in this kit" }
  validates_same_account :kit, :component
  validate { errors.add :component, "can't be a kit itself" if component&.kit? }
  validate { errors.add :component, "can't be the kit itself" if component_id.present? && component_id == kit_id }
end
