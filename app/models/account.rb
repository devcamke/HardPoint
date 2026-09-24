class Account < ApplicationRecord
  include CatalogueDefaults, DailySummary, Eventable, Isolation, LiveDashboard, LowStockDigest
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
  has_many :customers, dependent: :destroy
  has_many :barcodes
  has_many :product_units
  has_many :shifts, dependent: :destroy
  has_many :cash_movements
  has_many :sales, dependent: :destroy
  has_many :sale_returns, dependent: :destroy
  has_many :suppliers, dependent: :destroy
  has_many :purchase_orders, dependent: :destroy
  has_many :goods_receipts, dependent: :destroy
  has_many :supplier_invoices, dependent: :destroy
  has_many :supplier_payments, dependent: :destroy
  has_many :customer_orders, dependent: :destroy
  has_many :customer_payments, dependent: :destroy
  has_many :deposits, dependent: :destroy
  has_many :delivery_notes, dependent: :destroy

  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, message: "can only contain lowercase letters, numbers and dashes" },
    exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :max_cashier_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO code" }

  private
    def event_account
      self
    end
end
