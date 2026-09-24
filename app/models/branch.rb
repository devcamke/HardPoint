class Branch < ApplicationRecord
  belongs_to :account, default: -> { Current.account }

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :alphabetically, -> { order(:name) }
end
