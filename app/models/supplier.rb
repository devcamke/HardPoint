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

  scope :active, -> { where(active: true) }
  scope :alphabetically, -> { order(:name) }
  scope :search, ->(query) { query.present? ? where("suppliers.name ILIKE ?", "%#{sanitize_sql_like(query.squish)}%") : all }
end
