# Points that expire. Points earned in a month expire at the end of the month expiry_months later,
# and points are spent oldest first, so whatever a customer has used (spent, taken back, expired
# before) comes off their oldest points. Points held when expiry was turned on or shortened count
# as earned on expiry_starts_on, so no one loses points the day the rule changes.
module LoyaltyProgram::Expiry
  extend ActiveSupport::Concern

  EXPIRY_CHOICES = [ 6, 12, 18, 24, 36 ].freeze
  # Texts warning of points about to expire go out in the last WARNING_DAYS of the month.
  WARNING_DAYS = 14

  included do
    validates :expiry_months, inclusion: { in: EXPIRY_CHOICES }, allow_nil: true
    before_save :start_expiry, if: -> { will_save_change_to_expiry_months? && expiry_months }
  end

  class_methods do
    # Nightly, for every shop whose points expire. Safe to run more than once a day: points
    # already expired count as used, so they aren't expired twice.
    def expire_points
      where(enabled: true).where.not(expiry_months: nil).includes(:account).find_each do |program|
        Current.set(account: program.account) do
          program.expire_points
          program.warn_of_expiry
        end
      end
    end
  end

  def expires?
    expiry_months.present?
  end

  def local_today
    Time.current.in_time_zone(account.time_zone).to_date
  end

  # When points earned on a day run out: the end of the month expiry_months later.
  def expiry_date_for(earned_on)
    ([ earned_on, expiry_starts_on ].max + expiry_months.months).end_of_month
  end

  # Points earned before the first of this month, expiry_months ago, have run out.
  def expiry_cutoff(on: local_today)
    on.beginning_of_month - expiry_months.months
  end

  # { customer id => points } that have run out by the cutoff and aren't yet used or expired.
  def points_past(cutoff)
    return {} unless expires? && cutoff > expiry_starts_on

    earned = account.loyalty_entries.where(points: 1.., created_at: ...cutoff.in_time_zone(account.time_zone)).group(:customer_id).sum(:points)
    used = account.loyalty_entries.where(points: ...0, customer_id: earned.keys).group(:customer_id).sum(:points)
    earned.to_h { |id, points| [ id, points + used.fetch(id, 0) ] }.select { |_, points| points.positive? }
  end

  def expire_points(on: local_today)
    cutoff = expiry_cutoff(on: on)
    points_past(cutoff).each do |customer_id, points|
      account.loyalty_entries.create!(customer_id: customer_id, kind: "expired", points: -points, creator: nil,
        note: "earned before #{cutoff.strftime("%-d %B %Y")}")
    end
  end

  # Points that will run out at the end of this month, for the warning texts and the settings page.
  def points_expiring_this_month(on: local_today)
    points_past(on.next_month.beginning_of_month - expiry_months.months)
  end

  # One text a month to each customer whose points run out at the end of it.
  def warn_of_expiry(on: local_today)
    return unless text_points? && account.sms_enabled? && on >= on.end_of_month - WARNING_DAYS

    expiring = points_expiring_this_month(on: on)
    warned = account.sms_messages.where(purpose: "points_expiring", source_type: "Customer", source_id: expiring.keys,
      created_at: on.beginning_of_month.in_time_zone(account.time_zone)..).pluck(:source_id)
    account.customers.where(id: expiring.keys - warned).where.not(phone: [ nil, "" ]).find_each do |customer|
      Sms::Message.points_expiring(customer, points: expiring[customer.id], on: on.end_of_month)
    end
  end

  # A customer's unspent points by the day they run out, soonest first: [[date, points], ...].
  def expiry_schedule(customer)
    return [] unless expires?

    entries = customer.loyalty_entries.order(:created_at, :id).pluck(:created_at, :points)
    used = -entries.sum { |_, points| points.negative? ? points : 0 }
    zone = account.time_zone
    entries.filter_map { |at, points| [ expiry_date_for(at.in_time_zone(zone).to_date), points ] if points.positive? }
      .each_with_object(Hash.new(0)) do |(date, points), schedule|
        left = points - used
        used = [ used - points, 0 ].max
        schedule[date] += left if left.positive?
      end.sort
  end

  def next_expiry(customer)
    expiry_schedule(customer).first
  end

  private
    def start_expiry
      shortened = expiry_months_in_database && expiry_months < expiry_months_in_database
      self.expiry_starts_on = local_today if expiry_months_in_database.nil? || shortened || expiry_starts_on.nil?
    end
end
