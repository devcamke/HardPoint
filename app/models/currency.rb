# Another currency the shop takes at the till or buys in, and its rate: what one unit is worth in
# the shop's own currency (1 USD = 129.50 KES; 1 UGX = 0.0348 KES). Rates are set by the shop, as
# the bureau or the bank gives them; each payment, order and receipt keeps the rate it used.
class Currency < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  # Currencies whose notes have no cents in everyday use: amounts are shown whole.
  WHOLE = %w[ UGX TZS RWF BIF JPY KRW ].freeze
  COMMON = { "USD" => "US dollar", "EUR" => "Euro", "GBP" => "Pound sterling", "UGX" => "Ugandan shilling", "TZS" => "Tanzanian shilling",
             "RWF" => "Rwandan franc", "SSP" => "South Sudanese pound", "ETB" => "Ethiopian birr", "CNY" => "Chinese yuan", "AED" => "UAE dirham",
             "INR" => "Indian rupee", "ZAR" => "South African rand" }.freeze

  belongs_to :updater, class_name: "User", default: -> { Current.user }, optional: true

  normalizes :code, with: ->(code) { code.strip.upcase }

  validates :code, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter code, like USD" }, uniqueness: { scope: :account_id }
  validates :rate, numericality: { greater_than: 0 }
  validate { errors.add :code, "is the shop's own currency" if code == account&.currency }

  before_save { self.updater = Current.user if rate_changed? }

  scope :alphabetically, -> { order(:code) }
  scope :at_till, -> { where(accepted_at_till: true) }

  def self.decimals(code) = WHOLE.include?(code) ? 0 : 2

  def name
    COMMON[code] ? "#{COMMON[code]} (#{code})" : code
  end
  def event_name = code

  # Foreign amount (in its cents) to the shop's cents, rounded down: the shop never gives away a cent.
  def to_base_cents(foreign_cents, rate: self.rate)
    (foreign_cents.to_d * rate.to_d).floor
  end

  def to_foreign_cents(base_cents, rate: self.rate)
    (base_cents.to_d / rate.to_d).ceil
  end
end
