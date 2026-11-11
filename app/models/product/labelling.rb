# The shelf-label queue. A database trigger marks a product's label due when it's new or its price or name changes
# (label_due_at), keeping the price the shelf label still shows (label_old_price_cents). Stock › Labels lists them;
# printing the new labels clears them.
module Product::Labelling
  extend ActiveSupport::Concern

  included do
    scope :labels_due, -> { active.where.not(label_due_at: nil).order(:label_due_at, :name) }
  end

  class_methods do
    def labels_printed
      update_all(label_due_at: nil, label_old_price_cents: nil)
    end
  end

  # The shelf shows a price that's no longer the till's.
  def shelf_price_wrong? = label_old_price_cents.present? && label_old_price_cents != price_cents
end
