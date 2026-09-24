class Brand < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :alphabetically, -> { order(:name) }
end
