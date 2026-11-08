class Billing::Invoice < ApplicationRecord
  include AccountOwned, Monetary

  has_many :payments, dependent: :destroy

  enum :status, %w[ open paid void ].index_by(&:itself), default: :open
  # subscription: a period of the plan (plus add-ons); one_off: something platform staff billed,
  # such as setting the shop up, training or a hardware kit.
  enum :kind, %w[ subscription one_off ].index_by(&:itself), default: :subscription, scopes: true

  money_attribute :amount

  validates :plan, :period_start, :period_end, :due_on, presence: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :interval, inclusion: { in: Plan::INTERVALS }
  validates :description, presence: true, length: { maximum: 200 }, if: :one_off?

  before_validation(on: :create) do
    self.number ||= "HP-#{Date.current.year}-#{self.class.connection.select_value("SELECT nextval('billing_invoice_numbers')").to_s.rjust(6, "0")}"
  end

  scope :chronologically, -> { order(period_start: :desc, id: :desc) }

  def plan_name
    Plan.find(plan).name
  end

  def description
    one_off? ? super : "#{plan_name} plan#{" and add-ons" if add_ons.any?}, #{yearly? ? "a year" : "a month"} from #{period_start.to_fs(:long)} to #{(period_end - 1).to_fs(:long)}"
  end

  def yearly? = interval == "yearly"

  # Months the amount covers: twelve for a year (charged as ten), one otherwise.
  def months = yearly? ? 12 : 1
  def months_charged = yearly? ? Plan::YEARLY_MONTHS_CHARGED : 1

  def add_ons
    { branches: extra_branches, registers: extra_registers }.select { |_, count| count.positive? }
  end

  # What was billed, as [ description, quantity, amount ] lines. A subscription invoice's lines are
  # worked out from the plan's prices, so they add up to its amount as long as prices haven't changed.
  def lines
    return [ [ description, nil, amount_cents ] ] if one_off?

    plan = Plan.find(self.plan)
    lines = [ [ "HardPoint #{plan.name} plan", months, plan.price_cents * months_charged ] ]
    add_ons.each do |resource, count|
      lines << [ "Extra #{Plan::NOUNS.fetch(resource).pluralize(count)} × #{count}", months, count * plan.add_on_cents(resource).to_i * months_charged ]
    end
    lines
  end

  def overdue?(on = Date.current)
    open? && due_on < on
  end

  def mark_paid(payment)
    with_lock do
      return false unless open?

      update!(status: :paid, paid_at: payment.completed_at || Time.current)
    end
    account.subscription_paid(self)
    BillingMailer.with(invoice: self, payment: payment).payment_received.deliver_later
    true
  end
end
