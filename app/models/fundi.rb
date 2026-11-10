# A mason, plumber, electrician or other tradesperson who brings customers to the shop and earns a commission on
# what they buy. Named at the till (or on a quote or order); the commission is a ledger of its own (FundiEntry),
# earned when a sale completes, taken back by a void or a return, and paid out in cash or by M-Pesa (FundiPayout).
class Fundi < ApplicationRecord
  include AccountOwned, Eventable, Monetary
  tracks_lifecycle

  TRADES = { "mason" => "Mason", "plumber" => "Plumber", "electrician" => "Electrician", "carpenter" => "Carpenter",
             "painter" => "Painter", "welder" => "Welder", "tiler" => "Tiler", "roofer" => "Roofer", "other" => "Other" }.freeze

  has_many :entries, class_name: "FundiEntry", dependent: :restrict_with_error
  has_many :payouts, class_name: "FundiPayout", dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error
  has_many :customer_orders, dependent: :restrict_with_error

  normalizes :phone, with: ->(phone) { phone.gsub(/[^\d+]/, "").presence }

  validates :name, presence: true
  validates :trade, inclusion: { in: TRADES.keys }
  validates :commission_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }, allow_nil: true

  scope :alphabetically, -> { order(:name) }
  scope :active, -> { where(active: true) }

  scope :search, ->(query) do
    query = query.to_s.squish
    next all if query.blank?

    # Phone numbers match on their last nine digits, as customers' do.
    digits = query.gsub(/\D/, "").last(9)
    where("fundis.name ILIKE :like OR fundis.phone LIKE :phone", like: "%#{sanitize_sql_like(query)}%", phone: digits.length >= 4 ? "%#{digits}%" : nil)
  end

  # { fundi id => commission owed } for these fundis, from one query.
  def self.balances_by_id(ids = nil)
    entries = FundiEntry.all
    entries = entries.where(fundi_id: ids) if ids
    entries.group(:fundi_id).sum(:amount_cents)
  end

  def trade_name = TRADES.fetch(trade)

  def label = "#{name} · #{trade_name}"

  def balance_cents
    entries.sum(:amount_cents)
  end

  # The rate for one product: the fundi's own when the shop agreed one, else the product's category (or the nearest
  # parent category with a rate), else the shop's default.
  def commission_percent_for(product)
    return commission_percent if commission_percent

    category = product.category
    while category
      return category.fundi_commission_percent if category.fundi_commission_percent
      category = category.parent
    end
    account.fundi_commission_percent
  end
end
