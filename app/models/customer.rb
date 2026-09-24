class Customer < ApplicationRecord
  include AccountOwned, Eventable, Monetary
  tracks_lifecycle

  belongs_to :price_list, optional: true
  has_many :sales, dependent: :restrict_with_error

  money_attribute :credit_limit

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { phone.gsub(/[^\d+]/, "") }

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :credit_limit_cents, numericality: { greater_than_or_equal_to: 0 }
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

  # What the customer owes on account: sales put on account, less returns credited back.
  def balance_cents
    charged = Payment.on_account.joins(:sale).where(sales: { customer_id: id, status: "completed" }).sum(:amount_cents)
    credited = SaleReturn.joins(:sale).where(refund_method: "on_account", sales: { customer_id: id }).sum(:total_cents)
    charged - credited
  end

  def available_credit_cents
    [ credit_limit_cents - balance_cents, 0 ].max
  end

  def buys_on_account?
    credit_limit_cents.positive?
  end
end
