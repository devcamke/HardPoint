class StockLevel < ApplicationRecord
  include AccountOwned, PublishesWebhooks

  after_commit(on: %i[ create update ], if: -> { saved_change_to_quantity? }) { publish_webhook "stock.changed" }

  belongs_to :branch
  belongs_to :product

  validates_same_account :branch, :product
end
