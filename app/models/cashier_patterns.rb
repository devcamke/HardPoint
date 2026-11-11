# Each cashier against their own usual, for the owner's morning email. A day's voids, discounts, cash refunds and
# drawer openings without a sale are set beside the same cashier's last eight weeks, counting the days they worked
# (rang up a sale). What stands well out is flagged:
#
#   at least the floor          (3 voids, KES 1,000 of discounts, ...): small numbers aren't worth a look
#   more than twice their usual (the mean of their working days)
#   beyond their usual spread   (mean + 2 standard deviations, so a cashier whose days vary a lot isn't flagged often)
#
# A cashier with fewer than ten working days in the eight weeks has no usual yet and isn't flagged: a new cashier is
# better judged on the plain figures already in the email. The thresholds are the cashier's own, so a counter that
# discounts a lot to contractors isn't flagged every day for doing what it always does.
class CashierPatterns
  BASELINE_DAYS = 56
  MIN_WORKING_DAYS = 10
  SPREAD = 2

  Metric = Data.define(:key, :floor, :money)
  METRICS = [
    Metric.new(:voids, 3, false),
    Metric.new(:discount_cents, 1000_00, true),
    Metric.new(:cash_refund_cents, 1000_00, true),
    Metric.new(:drawer_openings, 3, false)
  ].freeze

  Flag = Data.define(:cashier, :metric, :value, :usual) do
    def description(currency: nil)
      amount = ->(value) { metric.money ? Money.format(value.round, **({ currency: } if currency).to_h) : value.round }
      usual_words =
        if metric.money then usual < 50 ? "usually none" : "usually about #{amount.(usual)} a day"
        elsif usual.zero? then "usually none"
        elsif usual < 1 then "usually under one a day"
        else "usually about #{usual.round} a day"
        end
      case metric.key
      when :voids then "voided #{value} #{"sale".pluralize(value)} (#{usual_words})"
      when :discount_cents then "gave #{amount.(value)} in discounts (#{usual_words})"
      when :cash_refund_cents then "refunded #{amount.(value)} in cash (#{usual_words})"
      when :drawer_openings then "opened the drawer without a sale #{value} #{"time".pluralize(value)} (#{usual_words})"
      end
    end
  end

  attr_reader :account, :date

  def initialize(account, date)
    @account, @date = account, date
  end

  # The day's flags, biggest jump first.
  def flags
    @flags ||= begin
      cashiers = account.users.where(id: today.keys).index_by(&:id)
      today.flat_map do |user_id, figures|
        days = baseline_working_days.fetch(user_id, [])
        next [] if days.size < MIN_WORKING_DAYS || cashiers[user_id].nil?

        METRICS.filter_map do |metric|
          value = figures.fetch(metric.key, 0)
          series = days.map { |day| baseline.dig(user_id, day, metric.key) || 0 }
          mean = series.sum.to_f / series.size
          spread = Math.sqrt(series.sum { (_1 - mean)**2 } / series.size)
          if value >= metric.floor && value > 2 * mean && value > mean + SPREAD * spread
            Flag.new(cashiers[user_id], metric, value, mean)
          end
        end
      end.sort_by { -(_1.value - _1.usual) / [ _1.metric.floor, 1 ].max }
    end
  end

  private
    # { cashier id => { metric => value } } for the day.
    def today
      @today ||= figures_between(date, date).transform_values { _1.fetch(date, {}) }.reject { |_, figures| figures.empty? }
    end

    # { cashier id => { day => { metric => value } } } for the eight weeks before the day.
    def baseline
      @baseline ||= figures_between(date - BASELINE_DAYS, date - 1)
    end

    # { cashier id => [ days they rang up a sale ] } in the eight weeks.
    def baseline_working_days
      @baseline_working_days ||= account.sales.where(status: %w[ completed voided ], completed_at: range(date - BASELINE_DAYS, date - 1))
        .group(:cashier_id, Arel.sql(local_date("sales.completed_at"))).count.keys
        .group_by(&:first).transform_values { |pairs| pairs.map { _2.to_date } }
    end

    def figures_between(from, to)
      figures = Hash.new { |hash, user| hash[user] = Hash.new { |days, day| days[day] = {} } }
      add = ->(rows, key) { rows.each { |(user_id, day), value| figures[user_id][day.to_date][key] = value.to_i if user_id } }

      add.(account.sales.where(status: "voided", voided_at: range(from, to)).group(:cashier_id, Arel.sql(local_date("sales.voided_at"))).count, :voids)
      completed = account.sales.where(status: %w[ completed voided ], completed_at: range(from, to))
      sale_discounts = completed.group(:cashier_id, Arel.sql(local_date("sales.completed_at"))).sum(:discount_cents)
      line_discounts = SaleLine.where(sale_id: completed.select(:id)).joins(:sale)
        .group("sales.cashier_id", Arel.sql(local_date("sales.completed_at"))).sum("sale_lines.discount_cents")
      add.(sale_discounts.merge(line_discounts) { |_, a, b| a + b }.select { _2.positive? }, :discount_cents)
      add.(account.sale_returns.where(refund_method: "cash", created_at: range(from, to))
        .group(:creator_id, Arel.sql(local_date("sale_returns.created_at"))).sum(:total_cents), :cash_refund_cents)
      add.(Event.where(account: account, action: "drawer_opened", created_at: range(from, to))
        .group(:creator_id, Arel.sql(local_date("events.created_at"))).count, :drawer_openings)
      figures
    end

    def range(from, to)
      zone = ActiveSupport::TimeZone[account.time_zone]
      zone.local(from.year, from.month, from.day).beginning_of_day..zone.local(to.year, to.month, to.day).end_of_day
    end

    def local_date(column)
      zone = ActiveSupport::TimeZone[account.time_zone].tzinfo.identifier
      "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{ActiveRecord::Base.connection.quote(zone)})::date"
    end
end
