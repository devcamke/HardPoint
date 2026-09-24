# One tool on a hire agreement, with the rates agreed when it went out and, once it's back, the days
# charged, the charge and any damage.
class HireLine < ApplicationRecord
  include AccountOwned

  # A day is 24 hours from when it went out, with an hour's grace for bringing it back.
  GRACE = 1.hour

  belongs_to :hire_agreement, inverse_of: :lines
  belongs_to :hire_item

  validates :damage_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :damage_note, :condition_note, length: { maximum: 250 }
  validates_same_account :hire_item

  def self.days_between(from, to)
    [ ((to.to_i - from.to_i - GRACE.to_i) / 1.day.to_f).ceil, 1 ].max
  end

  # Whole weeks at the weekly rate (where there is one), the rest by the day, never more than a week.
  def self.charge_for(days, daily_cents:, weekly_cents: nil)
    return days * daily_cents unless weekly_cents

    (days / 7) * weekly_cents + [ (days % 7) * daily_cents, weekly_cents ].min
  end

  def returned?
    returned_at.present?
  end

  def charge_until(time)
    self.class.charge_for(self.class.days_between(hire_agreement.started_at, time), daily_cents: daily_rate_cents, weekly_cents: weekly_rate_cents)
  end

  def return(at:, condition_note: nil, damage_cents: 0, damage_note: nil, needs_repair: false)
    days = self.class.days_between(hire_agreement.started_at, at)
    update!(returned_at: at, days_charged: days, charge_cents: self.class.charge_for(days, daily_cents: daily_rate_cents, weekly_cents: weekly_rate_cents),
      condition_note: condition_note.presence, damage_cents: damage_cents.to_i, damage_note: damage_note.presence)
    hire_item.update!(status: needs_repair || damage_cents.to_i.positive? ? "maintenance" : "available")
  end
end
