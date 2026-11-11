# Credit control. A shop can put an account on hold once an invoice is more than so many days overdue (Settings ›
# Preferences, credit_hold_after_days). While it's on hold nothing more goes on account, at the till or by confirming
# an order, without an owner's or manager's approval PIN. Paying the late invoices takes the hold off by itself, as
# the hold is worked out from what's owed each time rather than stored. An owner or manager can also lift it for a
# while, with a reason (an agreed payment plan, a cheque in the post).
module Customer::CreditHold
  extend ActiveSupport::Concern

  LIFT_DAYS = [ 7, 14, 30 ].freeze

  # Why an account is on hold: the most overdue invoice's lateness, and what's owed on invoices past the limit.
  Hold = Data.define(:days_overdue, :overdue_cents, :after_days) do
    def message(name)
      "#{name}'s account is on hold: #{Money.format(overdue_cents)} is more than #{after_days} days overdue (the oldest by #{days_overdue} days)"
    end
  end

  included do
    belongs_to :credit_hold_lifted_by, class_name: "User", optional: true
  end

  # The hold, or nil. Worked out once per customer object.
  def credit_hold
    return @credit_hold if defined?(@credit_hold)

    @credit_hold = begin
      after_days = account.credit_hold_after_days
      late = after_days.positive? && !credit_hold_lifted? ? open_invoices.select { _1.days_overdue > after_days } : []
      Hold.new(days_overdue: late.map(&:days_overdue).max, overdue_cents: late.sum(&:outstanding_cents), after_days:) if late.any?
    end
  end

  def on_credit_hold? = credit_hold.present?

  def credit_hold_lifted? = credit_hold_lifted_until.present? && credit_hold_lifted_until >= Date.current

  def lift_credit_hold(by:, days:, reason:)
    return errors.add(:base, "Say why the hold is lifted") && false if reason.blank?
    return errors.add(:base, "Lift it for #{LIFT_DAYS.to_sentence(last_word_connector: " or ")} days") && false unless days.to_i.in?(LIFT_DAYS)

    update!(credit_hold_lifted_until: days.to_i.days.from_now.to_date, credit_hold_lifted_by: by, credit_hold_lift_reason: reason.strip.first(200))
    remove_instance_variable(:@credit_hold) if defined?(@credit_hold)
    track_event "credit_hold_lifted", creator: by, days: days.to_i, reason: credit_hold_lift_reason
    true
  end

  def restore_credit_hold(by:)
    update!(credit_hold_lifted_until: nil, credit_hold_lifted_by: nil, credit_hold_lift_reason: nil)
    remove_instance_variable(:@credit_hold) if defined?(@credit_hold)
    track_event "credit_hold_restored", creator: by
  end

  def reload(...)
    remove_instance_variable(:@credit_hold) if defined?(@credit_hold)
    super
  end
end
