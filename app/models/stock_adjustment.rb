# A manual change to stock with a reason: opening stock, breakages, theft, stock found…
class StockAdjustment < ApplicationRecord
  include AccountOwned

  INCREASES = %w[ opening found ].freeze
  DECREASES = %w[ damaged stolen expired internal_use ].freeze
  REASONS = INCREASES + DECREASES + %w[ correction ]

  belongs_to :branch
  belongs_to :product
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true

  validates :reason, inclusion: { in: REASONS }
  validates :quantity, numericality: { other_than: 0 }
  validates_same_account :branch, :product
  validate :direction_matches_reason, :whole_units, :stock_stays_positive, :product_tracks_stock

  after_create { product.move_stock(branch: branch, quantity: quantity, reason: reason, source: self, note: note, creator: creator) }

  private
    def direction_matches_reason
      return unless quantity

      if reason.in?(INCREASES) && quantity.negative?
        errors.add :quantity, "must be positive for #{reason.humanize.downcase} stock"
      elsif reason.in?(DECREASES) && quantity.positive?
        errors.add :quantity, "must be negative (stock going out) for #{reason.humanize.downcase}"
      end
    end

    def whole_units
      errors.add :quantity, "must be a whole number of #{product.unit.name.pluralize.downcase}" if product && quantity && !product.quantity_allowed?(quantity)
    end

    def stock_stays_positive
      if product && branch && quantity && product.stock_at(branch) + quantity < 0
        errors.add :quantity, "would take stock below zero (#{product.stock_at(branch).to_s("F").delete_suffix(".0")} on hand)"
      end
    end

    def product_tracks_stock
      errors.add :product, "doesn't track stock" if product && !product.track_stock?
    end
end
