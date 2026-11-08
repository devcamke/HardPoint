# The billing round, run each morning for every shop:
#   - three days before a trial ends, a reminder;
#   - when a trial or paid period ends, the next period's invoice (a month, or a year for shops
#     paying yearly), due a week later;
#   - two days before it's due, a reminder;
#   - once it's overdue, the shop goes read-only until it's paid.
module Account::BillingCycle
  extend ActiveSupport::Concern

  TRIAL_REMINDER = 3.days
  PAYMENT_REMINDER = 2.days

  class_methods do
    def run_billing
      find_each do |account|
        Current.set(account: account) { account.bill }
      end
    end
  end

  def bill(now = Time.current)
    return if suspended? || closing?

    remind_trial_ending(now) if trialing?
    start_period(trial_ends_at.to_date) if trialing? && trial_ends_at <= now
    start_period(current_period_ends_at.to_date) if active? && current_period_ends_at && current_period_ends_at <= now && open_subscription_invoice.nil?

    if (invoice = open_invoice)
      remind_payment(invoice, now)
      lock_for_non_payment(invoice) if invoice.overdue?(now.to_date) && !read_only?
    end
  end

  # During the trial an owner can start paying straight away; the trial ends then.
  def start_subscription_now
    return open_subscription_invoice if open_subscription_invoice

    start_period(Date.current)
  end

  # Platform staff billing something outside the subscription: setting the shop up, training,
  # a hardware kit. Due in a week unless said otherwise; overdue, it locks the shop like any other.
  def issue_one_off_invoice(description, amount_cents, due_in: Plan::GRACE)
    invoice = billing_invoices.create!(kind: "one_off", description: description, amount_cents: amount_cents, plan: plan,
      period_start: Date.current, period_end: Date.current, due_on: Date.current + due_in)
    update!(subscription_status: "payment_due") if active?
    track_event "invoice_issued", creator: nil, invoice: invoice.number, amount: invoice.amount_cents, description: description, **platform_particulars
    BillingMailer.with(invoice: invoice).invoice_issued.deliver_later
    invoice
  end

  def subscription_paid(invoice)
    if invoice.one_off?
      update!(subscription_status: status_from_billing) unless suspended?
    else
      update!(subscription_status: suspended? ? "suspended" : "active", current_period_ends_at: invoice.period_end.in_time_zone(time_zone).beginning_of_day,
              trial_ends_at: [ trial_ends_at, Time.current ].compact.min)
    end
  end

  def billing_recipients
    users.where(memberships: { role: "owner" }).pluck(:email_address)
  end

  private
    def start_period(start)
      invoice = billing_invoices.create!(plan: plan, interval: billing_interval, extra_branches: extra_branches, extra_registers: extra_registers,
        period_start: start, period_end: start + (yearly? ? 1.year : 1.month), amount_cents: period_price_cents,
        due_on: [ start, Date.current ].max + Plan::GRACE)
      update!(subscription_status: "payment_due") unless read_only?
      track_event "invoice_issued", creator: nil, invoice: invoice.number, amount: invoice.amount_cents
      BillingMailer.with(invoice: invoice).invoice_issued.deliver_later
      invoice
    end

    def remind_trial_ending(now)
      return if trial_reminder_sent_at || trial_ends_at.nil? || trial_ends_at > now + TRIAL_REMINDER || trial_ends_at <= now

      update!(trial_reminder_sent_at: now)
      BillingMailer.with(account: self).trial_ending.deliver_later
    end

    def remind_payment(invoice, now)
      return if invoice.reminded_at || invoice.due_on > (now + PAYMENT_REMINDER).to_date || invoice.overdue?(now.to_date)

      invoice.update!(reminded_at: now)
      BillingMailer.with(invoice: invoice).payment_reminder.deliver_later
    end

    def lock_for_non_payment(invoice)
      update!(subscription_status: "read_only")
      track_event "made_read_only", creator: nil, invoice: invoice.number
      BillingMailer.with(invoice: invoice).read_only.deliver_later
    end
end
