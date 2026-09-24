class Customer < ApplicationRecord
  include AccountOwned, Eventable, Monetary, Receivables, PublishesWebhooks
  tracks_lifecycle
  publishes_webhooks "customer"

  belongs_to :price_list, optional: true
  has_many :sales, dependent: :restrict_with_error
  has_many :customer_orders, dependent: :restrict_with_error

  money_attribute :credit_limit

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { phone.gsub(/[^\d+]/, "") }

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :credit_limit_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :payment_terms_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates_same_account :price_list

  scope :alphabetically, -> { order(:name) }
  scope :search, ->(query) do
    query = query.to_s.squish
    next all if query.blank?

    # Phone numbers match on their last nine digits, so 0722 000 111 finds +254722000111.
    digits = query.gsub(/\D/, "").last(9)
    phone_match = digits.length >= 4 ? "%#{digits}%" : nil
    where("customers.name ILIKE :like OR customers.phone LIKE :phone", like: "%#{sanitize_sql_like(query)}%", phone: phone_match)
  end

  # Customers pay their account to the Paybill with their phone number as the account number.
  def self.find_by_account_number(reference)
    digits = reference.to_s.gsub(/\D/, "").last(9)
    where("customers.phone LIKE ?", "%#{digits}").first if digits.length == 9
  end

  def available_credit_cents
    [ credit_limit_cents - balance_cents, 0 ].max
  end

  def buys_on_account?
    credit_limit_cents.positive?
  end
end
