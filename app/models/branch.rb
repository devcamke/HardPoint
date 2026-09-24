class Branch < ApplicationRecord
  include Eventable
  tracks_lifecycle

  belongs_to :account, default: -> { Current.account }
  has_many :registers, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :alphabetically, -> { order(:name) }
end
