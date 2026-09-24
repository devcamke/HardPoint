# Named prices for groups of customers, e.g. contractors or wholesale buyers.
class PriceList < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  has_many :items, class_name: "PriceListItem", dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :alphabetically, -> { order(:name) }
end
