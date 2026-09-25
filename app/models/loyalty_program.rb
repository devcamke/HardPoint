# A shop's points scheme. Named customers earn points on what they pay for (points_per_100 for
# every 100 of the shop's currency) and spend them at the till, each point worth point_value.
class LoyaltyProgram < ApplicationRecord
  include AccountOwned, Eventable, Monetary
  tracks_lifecycle only: :update

  money_attribute :point_value

  validates :points_per_100, numericality: { greater_than: 0 }
  validates :point_value_cents, numericality: { greater_than: 0, only_integer: true }
  validates :min_redeem_points, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def event_name = "Loyalty points"

  # Whole points only, rounded down.
  def points_for(cents)
    (cents.to_d / 100_00 * points_per_100).floor
  end

  def value_cents(points)
    points * point_value_cents
  end

  # Points needed to pay an amount, rounded up so a point is never worth more than it should.
  def points_to_pay(cents)
    (cents.to_d / point_value_cents).ceil
  end

  # What every customer's unspent points are worth, if all were spent.
  def liability_cents
    value_cents(account.loyalty_entries.sum(:points))
  end

  # Cents off per 100 spent, as a percentage: what the scheme gives back.
  def reward_percent
    (points_per_100 * point_value_cents / 100).round(2)
  end
end
