# A shop's plan and whether it's paid up. Shops start on a trial of the Business plan; each period
# (from the trial's end) brings an invoice due a week later. Unpaid after that, the shop goes
# read-only: everything can be seen and exported, nothing changed, until it's paid. The platform
# can suspend a shop outright.
#
# On top of the plan a shop can buy extra branches and tills (add-ons, priced per month by the
# plan) and choose to be billed yearly, at ten months' price for twelve.
module Account::Subscription
  extend ActiveSupport::Concern

  STATUSES = %w[ trialing active payment_due read_only suspended ].freeze

  included do
    has_many :billing_invoices, -> { order(period_start: :desc) }, class_name: "Billing::Invoice", dependent: :destroy
    has_many :billing_payments, class_name: "Billing::Payment", dependent: :destroy

    validates :plan, inclusion: { in: -> { Plan.all.map(&:key) } }
    validates :subscription_status, inclusion: { in: STATUSES }
    validates :billing_interval, inclusion: { in: Plan::INTERVALS }
    validates :extra_branches, :extra_registers, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 99 }

    before_create { self.trial_ends_at ||= Plan::TRIAL.from_now }
  end

  def subscription_plan
    Plan.find(plan)
  end

  STATUSES.each do |status|
    define_method(:"#{status}?") { subscription_status == status }
  end

  def yearly? = billing_interval == "yearly"

  # Nothing can be changed, only looked at, exported and paid for.
  def locked?
    read_only? || suspended? || closing?
  end

  def trial_days_left
    [ ((trial_ends_at - Time.current) / 1.day).ceil, 0 ].max if trialing? && trial_ends_at
  end

  # The invoice to pay next: the one due soonest, subscription or one-off.
  def open_invoice
    billing_invoices.open.order(:due_on, :id).first
  end

  def open_subscription_invoice
    billing_invoices.open.subscription.order(:due_on, :id).first
  end

  # What's in use now against the plan's limits.
  def usage
    { branches: branches.count, registers: registers.active.count, users: memberships.count }
  end

  # How many of a resource this shop may have: the plan's allowance plus any add-ons bought.
  # nil means no limit.
  def limit(resource, on: subscription_plan, extras: add_ons)
    base = on.limit(resource) or return nil
    base + extras.fetch(resource, 0)
  end

  def add_ons
    { branches: extra_branches, registers: extra_registers }
  end

  def within_plan?(target = subscription_plan, extras: add_ons)
    usage.all? { |resource, count| (limit = limit(resource, on: target, extras: extras)).nil? || count <= limit }
  end

  def room_for?(resource, more = 1)
    limit = limit(resource)
    limit.nil? || usage.fetch(resource) + more <= limit
  end

  # What the next invoice will be for a month: the plan plus the add-ons.
  def monthly_price_cents(on: subscription_plan, extras: add_ons)
    on.price_cents + Plan::ADD_ONS.sum { |resource| extras.fetch(resource, 0) * on.add_on_cents(resource).to_i }
  end

  # What the next invoice will come to, for the period it covers.
  def period_price_cents
    yearly? ? monthly_price_cents * Plan::YEARLY_MONTHS_CHARGED : monthly_price_cents
  end

  # Upgrades take effect at once; a smaller plan only if what's in use fits it. The new price
  # applies from the next invoice. Add-ons carry over unless the new plan has no limits.
  def change_plan(key, by: Current.user)
    target = Plan.find(key)
    extras = target.add_ons? ? add_ons : { branches: 0, registers: 0 }
    unless within_plan?(target, extras: extras)
      over = Plan::RESOURCES.select { |resource| (limit = limit(resource, on: target, extras: extras)) && usage[resource] > limit }
      errors.add :plan, "#{target.name} allows #{over.map { Plan.allowance(limit(_1, on: target, extras: extras), _1) }.to_sentence}; this shop has more"
      return false
    end

    previous = plan
    update!(plan: target.key, extra_branches: extras[:branches], extra_registers: extras[:registers])
    track_event "plan_changed", creator: by, from: previous, to: target.key, **platform_particulars
  end

  # Buying or giving up extra branches and tills, and choosing monthly or yearly billing. More
  # room applies at once; less only if what's in use still fits. Prices change from the next invoice.
  def change_add_ons(extra_branches: self.extra_branches, extra_registers: self.extra_registers, billing_interval: self.billing_interval, by: Current.user)
    unless subscription_plan.add_ons? || (extra_branches.to_i.zero? && extra_registers.to_i.zero?)
      errors.add :base, "#{subscription_plan.name} has no limits, so there's nothing to add"
      return false
    end

    # Giving an add-on back only when the shop no longer needs it; buying more is always fine.
    extras = { branches: extra_branches.to_i, registers: extra_registers.to_i }
    over = Plan::ADD_ONS.select { |resource| extras[resource] < add_ons[resource] && (limit = limit(resource, extras: extras)) && usage[resource] > limit }
    if over.any?
      errors.add :base, "This shop has more than #{over.map { Plan.allowance(limit(_1, extras: extras), _1) }.to_sentence} in use"
      return false
    end

    before = { extra_branches: self.extra_branches, extra_registers: self.extra_registers, billing_interval: self.billing_interval }
    return true unless update(extra_branches: extras[:branches], extra_registers: extras[:registers], billing_interval: billing_interval.to_s)
    return true if before == { extra_branches: self.extra_branches, extra_registers: self.extra_registers, billing_interval: self.billing_interval }

    track_event "add_ons_changed", creator: by, extra_branches: self.extra_branches, extra_registers: self.extra_registers,
      billing_interval: self.billing_interval, monthly_price: monthly_price_cents, **platform_particulars
  end

  # Platform support: a longer trial, e.g. while a shop finishes setting up.
  def extend_trial(days)
    return false unless trialing?

    update!(trial_ends_at: [ trial_ends_at, Time.current ].compact.max + days.to_i.days, trial_reminder_sent_at: nil)
    track_event "trial_extended", creator: nil, days: days.to_i, until: trial_ends_at.to_date.iso8601, **platform_particulars
  end

  # Platform support: shut a shop for abuse or at its owner's request. It can be looked at, not used.
  def suspend(reason)
    update!(subscription_status: "suspended", suspended_reason: reason.presence)
    track_event "suspended", creator: nil, reason: reason.presence, **platform_particulars
  end

  # Back to whatever its billing says it should be.
  def restore
    return false unless suspended?

    update!(subscription_status: status_from_billing, suspended_reason: nil)
    track_event "restored", creator: nil, status: subscription_status, **platform_particulars
  end

  # Money received outside M-Pesa and Paystack (a bank transfer, say), recorded by platform staff.
  def record_manual_payment(reference)
    invoice = open_invoice or return false
    payment = invoice.payments.create!(account: self, provider: "manual", amount_cents: invoice.amount_cents,
      reference: "MANUAL-#{invoice.number}-#{SecureRandom.hex(3)}", user: nil)
    payment.succeed(receipt: reference.presence || "Manual")
  end

  private
    def status_from_billing
      if (invoice = open_invoice)
        invoice.overdue? ? "read_only" : "payment_due"
      elsif current_period_ends_at.nil? && trial_ends_at&.future?
        "trialing"
      else
        "active"
      end
    end

    # Who at HardPoint did it, when it was done from the platform admin.
    def platform_particulars
      { administrator: Current.administrator&.email_address }.compact
    end
end
