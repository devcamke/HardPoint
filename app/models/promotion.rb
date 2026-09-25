# A price offer for a while: a percentage off, or "buy 10, get 1 free", on chosen products or whole
# categories, at every branch or some. At the till each line gets the one promotion that saves the
# customer most; promotions don't stack with each other or with a price list (the better price wins),
# and what they take off is kept apart from discounts given by hand.
class Promotion < ApplicationRecord
  include AccountOwned, Eventable
  tracks_lifecycle

  KINDS = %w[ percent_off buy_get ].freeze

  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :sale_lines, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :starts_on, :ends_on, presence: true
  validates :percent_off, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: :percent_off?
  validates :buy_quantity, :free_quantity, numericality: { greater_than: 0 }, if: :buy_get?
  validate { errors.add :ends_on, "can't be before it starts" if starts_on && ends_on && ends_on < starts_on }
  validate { errors.add :base, "Choose at least one product or category" if product_ids.empty? && category_ids.empty? }
  validate :targets_belong_to_the_shop

  after_commit { account.forget_running_promotions }

  before_validation { self.product_ids = product_ids.compact_blank.map(&:to_i).uniq; self.category_ids = category_ids.compact_blank.map(&:to_i).uniq; self.branch_ids = branch_ids.compact_blank.map(&:to_i).uniq }

  scope :running, ->(on = Date.current) { where(active: true).where("promotions.starts_on <= :on AND promotions.ends_on >= :on", on: on) }
  scope :for_branch, ->(branch) { where("cardinality(promotions.branch_ids) = 0 OR ? = ANY(promotions.branch_ids)", branch.id) }
  scope :newest_first, -> { order(starts_on: :desc, id: :desc) }

  def percent_off? = kind == "percent_off"
  def buy_get? = kind == "buy_get"

  def status(on = Date.current)
    if !active? then "paused"
    elsif on < starts_on then "upcoming"
    elsif on > ends_on then "ended"
    else "running"
    end
  end

  def covers?(product)
    product_ids.include?(product.id) || (product.category_id && category_ids.include?(product.category_id))
  end

  def available_at?(branch)
    branch_ids.empty? || branch_ids.include?(branch&.id)
  end

  def offer
    percent_off? ? "#{percent_off.to_d.to_s("F").delete_suffix(".0")}% off" : "Buy #{quantity_text(buy_quantity)}, get #{quantity_text(free_quantity)} free"
  end

  # What this promotion takes off a line priced at unit_price_cents each (the customer's own price).
  # A percentage comes off the shelf price, so a contractor whose price is already lower gets
  # whichever is better, never both. Free items are the customer's own price.
  def saving_cents(product:, quantity:, unit_price_cents:, product_unit: nil)
    quantity = quantity.to_d
    return 0 unless quantity.positive? && covers?(product)

    if percent_off?
      shelf = product_unit ? product_unit.effective_price_cents : product.price_cents
      offer_price = (shelf * (100 - percent_off.to_d) / 100).round
      [ ((unit_price_cents - offer_price) * quantity).round, 0 ].max
    else
      free = (quantity / (buy_quantity + free_quantity)).floor * free_quantity
      (free * unit_price_cents).round
    end
  end

  # The unit price with a percentage off, for quotes and online orders (free items only happen at the till).
  def price_cents_for(product, unit_price_cents, product_unit: nil)
    return unit_price_cents unless percent_off? && covers?(product)

    shelf = product_unit ? product_unit.effective_price_cents : product.price_cents
    [ unit_price_cents, (shelf * (100 - percent_off.to_d) / 100).round ].min
  end

  def products
    account.products.where(id: product_ids).or(account.products.where(category_id: category_ids.presence || [ 0 ]))
  end

  private
    def quantity_text(value) = value.to_d.to_s("F").delete_suffix(".0")

    def targets_belong_to_the_shop
      return unless account

      errors.add :base, "Some products aren't this shop's" if product_ids.any? && account.products.where(id: product_ids).count != product_ids.size
      errors.add :base, "Some categories aren't this shop's" if category_ids.any? && account.categories.where(id: category_ids).count != category_ids.size
      errors.add :base, "Some branches aren't this shop's" if branch_ids.any? && account.branches.where(id: branch_ids).count != branch_ids.size
    end
end
