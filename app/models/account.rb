class Account < ApplicationRecord
  include CatalogueDefaults, DailySummary, Eventable, Isolation, LiveDashboard, LowStockDigest, Subscription, BillingCycle, Closure
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
  has_many :stock_batches, dependent: :delete_all
  has_many :stock_adjustments, dependent: :delete_all
  has_many :stock_transfers, dependent: :destroy
  has_many :stock_counts, dependent: :destroy
  has_many :product_imports, dependent: :delete_all
  has_many :customers, dependent: :destroy
  has_many :barcodes
  has_many :product_units
  has_many :price_list_items
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
  has_many :mpesa_shortcodes, class_name: "Mpesa::Shortcode", dependent: :destroy
  has_many :mpesa_stk_requests, class_name: "Mpesa::StkRequest", dependent: :destroy
  has_many :mpesa_transactions, class_name: "Mpesa::Transaction", dependent: :destroy
  has_many :etims_devices, class_name: "Etims::Device", dependent: :destroy
  has_many :etims_submissions, class_name: "Etims::Submission", dependent: :destroy
  has_many :sms_messages, class_name: "Sms::Message", dependent: :delete_all
  has_many :support_requests, dependent: :delete_all
  has_one :storefront, dependent: :destroy
  has_many :hire_items, dependent: :destroy
  has_many :hire_agreements, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :currencies, dependent: :delete_all
  has_many :promotions, dependent: :delete_all
  has_one :loyalty_program, dependent: :destroy
  has_many :loyalty_entries, dependent: :delete_all

  # Promotions running today, looked up once per request (the till, the store's product lists),
  # and forgotten when one is saved.
  def running_promotions
    @running_promotions = nil unless @running_promotions_on == Date.current
    @running_promotions_on = Date.current
    @running_promotions ||= promotions.running(Date.current).order(:id).to_a
  end

  def forget_running_promotions
    @running_promotions = nil
  end
  has_many :api_keys, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy
  has_many :webhook_deliveries, dependent: :delete_all

  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, message: "can only contain lowercase letters, numbers and dashes" },
    exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :max_cashier_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO code" }

  private
    # Subscription and setup bookkeeping gets its own events (plan_changed, suspended…), not "changed shop settings".
    SUBSCRIPTION_ATTRIBUTES = %w[ plan subscription_status trial_ends_at current_period_ends_at trial_reminder_sent_at suspended_reason
      onboarding_completed_at taxes_confirmed_at test_receipt_printed_at deletion_scheduled_for deletion_requested_by_id ].freeze

    def event_account
      self
    end

    def tracked_changes
      super.except(*SUBSCRIPTION_ATTRIBUTES)
    end
end
