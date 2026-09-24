# HardPoint's price plans, per shop per month. Limits are what's in use at once: active branches,
# tills, staff and products. nil means no limit.
class Plan < Data.define(:key, :name, :price_cents, :branches, :registers, :users, :products, :api, :blurb)
  TRIAL = 30.days
  GRACE = 7.days
  RESOURCES = %i[ branches registers users products ].freeze

  def self.all
    [
      new("starter", "Starter", 2_500_00, 1, 2, 3, 2_000, false, "One shop, a couple of tills"),
      new("business", "Business", 6_500_00, 3, 8, 15, 20_000, true, "A growing shop with a yard or second branch"),
      new("enterprise", "Enterprise", 15_000_00, nil, nil, nil, nil, true, "Many branches, no limits")
    ]
  end

  def self.find(key)
    all.find { _1.key == key.to_s } or raise ArgumentError, "No plan called #{key}"
  end

  NOUNS = { branches: "branch", registers: "till", users: "staff login", products: "product" }.freeze

  # "1 branch", "2 tills", "2,000 products"
  def self.allowance(count, resource)
    "#{ActiveSupport::NumberHelper.number_to_delimited(count)} #{NOUNS.fetch(resource).pluralize(count)}"
  end

  def limit(resource) = public_send(resource)
  alias_method :api?, :api
  def to_param = key

  def price
    Money.format(price_cents, currency: "KES")
  end
end
