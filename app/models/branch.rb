class Branch < ApplicationRecord
  include Eventable
  tracks_lifecycle

  belongs_to :account, default: -> { Current.account }
  has_many :registers, dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :code, format: { with: /\A[A-Z0-9]{1,6}\z/, message: "must be 1 to 6 letters or numbers" }

  normalizes :code, with: ->(code) { code.strip.upcase }
  # Receipt numbers start with the branch code, e.g. MOI-000123.
  before_validation(on: :create) { self.code = name.to_s.upcase.gsub(/[^A-Z0-9]/, "").first(3).presence || "BR" if code.blank? }

  scope :alphabetically, -> { order(:name) }
end
