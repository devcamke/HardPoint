# A shop's plan and whether it's paid up. Shops start on a trial of the Business plan; each month
# (from the trial's end) brings an invoice due a week later. Unpaid after that, the shop goes
# read-only: everything can be seen and exported, nothing changed, until it's paid. The platform
# can suspend a shop outright.
module Account::Subscription
  extend ActiveSupport::Concern

  STATUSES = %w[ trialing active payment_due read_only suspended ].freeze

  included do
    has_many :billing_invoices, -> { order(period_start: :desc) }, class_name: "Billing::Invoice", dependent: :destroy
    has_many :billing_payments, class_name: "Billing::Payment", dependent: :destroy

    validates :plan, inclusion: { in: -> { Plan.all.map(&:key) } }
    validates :subscription_status, inclusion: { in: STATUSES }

    before_create { self.trial_ends_at ||= Plan::TRIAL.from_now }
  end

  def subscription_plan
    Plan.find(plan)
  end

  STATUSES.each do |status|
    define_method(:"#{status}?") { subscription_status == status }
  end

  # Nothing can be changed, only looked at, exported and paid for.
  def locked?
    read_only? || suspended? || closing?
  end

  def trial_days_left
    [ ((trial_ends_at - Time.current) / 1.day).ceil, 0 ].max if trialing? && trial_ends_at
  end

  def open_invoice
    billing_invoices.open.order(:due_on).first
  end

  # What's in use now against the plan's limits.
  def usage
    { branches: branches.count, registers: registers.active.count, users: memberships.count, products: products.active.count }
  end

  def within_plan?(target = subscription_plan)
    usage.all? { |resource, count| target.limit(resource).nil? || count <= target.limit(resource) }
  end

  def room_for?(resource, more = 1)
    limit = subscription_plan.limit(resource)
    limit.nil? || usage.fetch(resource) + more <= limit
  end

  # Upgrades take effect at once; a smaller plan only if what's in use fits it. The new price
  # applies from the next invoice.
  def change_plan(key, by: Current.user)
    target = Plan.find(key)
    unless within_plan?(target)
      over = Plan::RESOURCES.select { |resource| target.limit(resource) && usage[resource] > target.limit(resource) }
      errors.add :plan, "#{target.name} allows #{over.map { Plan.allowance(target.limit(_1), _1) }.to_sentence}; this shop has more"
      return false
    end

    previous = plan
    update!(plan: target.key)
    track_event "plan_changed", creator: by, from: previous, to: target.key, **platform_particulars
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
