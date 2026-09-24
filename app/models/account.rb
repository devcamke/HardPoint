class Account < ApplicationRecord
  include Isolation

  RESERVED_SUBDOMAINS = %w[ admin api app assets blog cdn docs help mail smtp status support www ].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :sessions, dependent: :delete_all
  has_many :branches, dependent: :destroy

  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, message: "can only contain lowercase letters, numbers and dashes" },
    exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO code" }
end
