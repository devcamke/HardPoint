class Supplier < ApplicationRecord
  include AccountOwned, Eventable, Payables
  tracks_lifecycle

  has_many :supplier_products, dependent: :destroy
  has_many :products, through: :supplier_products
  has_many :purchase_orders, dependent: :restrict_with_error
  has_many :goods_receipts, dependent: :restrict_with_error

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { phone.gsub(/[^\d+]/, "") }

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :payment_terms_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate { errors.add :currency, "must be one of the shop's currencies (Settings › Currencies)" if currency && account && !account.currencies.exists?(code: currency) }
  validate(on: :update) { errors.add :currency, "can't change once there are orders, invoices or payments" if currency_changed? && trading? }

  normalizes :currency, with: ->(code) { code.strip.upcase.presence }

  # A supplier who invoices in another currency (an importer in dollars): their orders, invoices and
  # payments are all in it. Nil is the shop's own currency.
  def currency_code = currency || account.currency
  def foreign? = currency.present?

  def exchange_currency
    account.currencies.find_by(code: currency) if foreign?
  end

  def current_rate
    exchange_currency&.rate
  end

  # What an amount in the supplier's currency is worth today, for totals across suppliers.
  def to_base_cents(cents)
    foreign? && current_rate ? (cents * current_rate).round : cents
  end

  def trading?
    purchase_orders.exists? || supplier_invoices.exists? || supplier_payments.exists?
  end

  scope :active, -> { where(active: true) }
  scope :alphabetically, -> { order(:name) }
  scope :search, ->(query) { query.present? ? where("suppliers.name ILIKE ?", "%#{sanitize_sql_like(query.squish)}%") : all }
end
