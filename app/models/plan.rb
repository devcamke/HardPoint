# HardPoint's price plans, per shop per month. Limits are what's in use at once: active branches,
# tills and staff logins; nil means no limit. Products are never limited: a hardware shop carries
# thousands of lines, and counting them would only punish good record-keeping.
#
# A shop that needs one more branch or till than its plan allows buys it as an add-on
# (extra_branch_cents / extra_register_cents a month each) rather than jumping a whole plan.
# Paying a year at a time costs YEARLY_MONTHS_CHARGED months: two months free.
#
# These are the launch prices. An add-on always costs less than the step up to the next plan.
class Plan < Data.define(:key, :name, :price_cents, :branches, :registers, :users, :extra_branch_cents, :extra_register_cents, :api, :blurb)
  TRIAL = 30.days
  GRACE = 7.days
  RESOURCES = %i[ branches registers users ].freeze
  ADD_ONS = %i[ branches registers ].freeze
  INTERVALS = %w[ monthly yearly ].freeze
  YEARLY_MONTHS_CHARGED = 10

  # One-off services, quoted on the pricing page. They're billed by platform staff as one-off
  # invoices (Billing::Invoice#one_off?), so the amounts here are "from" prices.
  SETUP_CENTS = 15_000_00

  def self.all
    [
      new("solo", "Solo", 1_500_00, 1, 1, 2, 750_00, 300_00, false, "One counter, one till"),
      new("starter", "Starter", 2_500_00, 1, 2, 5, 750_00, 300_00, false, "One shop, a couple of tills"),
      new("business", "Business", 3_500_00, 2, 4, 10, 750_00, 300_00, true, "A growing shop with a yard or second branch"),
      new("unlimited", "Unlimited", 5_000_00, nil, nil, nil, nil, nil, true, "Many branches, no limits")
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

  # What one more of a resource costs a month, or nil when the plan has no limit to go past.
  def add_on_cents(resource)
    { branches: extra_branch_cents, registers: extra_register_cents }.fetch(resource)
  end

  def add_ons? = ADD_ONS.any? { add_on_cents(_1) }

  def price
    Money.format(price_cents, currency: "KES")
  end

  def yearly_price_cents = price_cents * YEARLY_MONTHS_CHARGED

  def yearly_price
    Money.format(yearly_price_cents, currency: "KES")
  end
end
