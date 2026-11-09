class StockLevel < ApplicationRecord
  include AccountOwned, PublishesWebhooks

  after_commit(on: %i[ create update ], if: -> { saved_change_to_quantity? }) { publish_webhook "stock.changed" }

  belongs_to :branch
  belongs_to :product

  # The branch's own reorder level for the product; nil means the product's applies here.
  validates :reorder_level, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates_same_account :branch, :product
end
