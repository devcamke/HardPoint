class Account < ApplicationRecord
  include CatalogueDefaults, Eventable, Isolation, LowStockDigest
  # Creation is recorded by Signup, once the new account is current.
  tracks_lifecycle only: :update

  RESERVED_SUBDOMAINS = %w[ admin api app assets blog cdn docs help mail smtp status support www ].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :sessions, dependent: :delete_all
  has_many :branches, dependent: :destroy
  has_many :account_events, class_name: "Event", dependent: :delete_all
  has_many :registers, dependent: :destroy

  has_many :categories, dependent: :destroy
  has_many :brands, dependent: :destroy
  has_many :units, dependent: :destroy
  has_many :tax_rates, dependent: :destroy
  has_many :price_lists, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :stock_levels, dependent: :delete_all
  has_many :stock_movements, dependent: :delete_all
  has_many :stock_adjustments, dependent: :delete_all
  has_many :stock_transfers, dependent: :destroy
  has_many :stock_counts, dependent: :destroy
  has_many :product_imports, dependent: :delete_all

  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, message: "can only contain lowercase letters, numbers and dashes" },
    exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO code" }

  private
    def event_account
      self
    end
end
