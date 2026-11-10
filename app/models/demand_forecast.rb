# How much of each product a branch is likely to need, learnt from its own history, for the reorder list:
#
#   demand    = what sold over the look-back period, plus what the till turned away (each day's biggest shortfall:
#               a customer asked, the shelf was short), per day
#   season    = with a year of history, how this time last year compared with the year as a whole (0.5 to 2 times),
#               so the rains or the building season show up before they arrive
#   safety    = a margin for busy days: 1.65 standard deviations of daily sales over the lead time (about 19 days
#               in 20 covered)
#   lead time = how long the supplier really takes, from sending an order to the delivery arriving (the middle of
#               its last deliveries, once there are two), else what's set on the supplier's product, else the shop's
#
# The suggested reorder level is what's needed to last the lead time, plus the safety margin.
class DemandForecast
  SAFETY_FACTOR = 1.65
  SEASON_RANGE = (0.5..2.0)
  LEAD_TIME_SAMPLES = 2
  LEAD_TIME_HISTORY = 365.days

  # Days with a sale in the look-back period: lowering a reorder level waits for this much evidence.
  EVIDENCE_DAYS = 10

  Forecast = Data.define(:daily, :sold, :unmet, :season, :safety, :lead_time, :lead_time_measured, :suggested_level, :sales_days) do
    # In words, for the reorder list: only what changed the answer.
    def notes
      [ ("#{unmet.to_d.round(1).to_s("F").delete_suffix(".0")} more asked for at the till" if unmet.positive?),
        (season > 1.05 ? "busier season: #{((season - 1) * 100).round}% up on usual" : season < 0.95 ? "quieter season: #{((1 - season) * 100).round}% down" : nil),
        ("deliveries take #{lead_time} days" if lead_time_measured) ].compact
    end
  end

  attr_reader :account, :branch

  def initialize(account, branch)
    @account, @branch = account, branch
  end

  def lookback = account.reorder_lookback_days

  # For a product, given the lead time its supplier product says (nil for none).
  def for(product, supplier_product: nil)
    sold_quantity = sold.fetch(product.id, 0).to_d
    unmet_quantity = unmet.fetch(product.id, 0).to_d
    lead_time, measured = lead_time_for(supplier_product)
    season = seasonal_factor(product.id, lead_time)
    daily = (sold_quantity + unmet_quantity) / lookback * season
    safety = SAFETY_FACTOR * deviation(product.id) * Math.sqrt(lead_time)
    level = daily * lead_time + safety
    level = product.unit.fractional? ? level.round(1, BigDecimal::ROUND_UP) : level.ceil
    Forecast.new(daily:, sold: sold_quantity, unmet: unmet_quantity, season:, safety: safety.to_d, lead_time:, lead_time_measured: measured, suggested_level: level,
      sales_days: daily_sales.fetch(product.id, {}).size)
  end

  # Products with any demand here: sold, or asked for and turned away.
  def product_ids = sold.keys | unmet.keys

  private
    def since = lookback.days.ago

    def sold
      @sold ||= StockMovement.where(branch: branch, reason: %w[ sold returned ], created_at: since..)
        .group(:product_id).sum(:quantity).transform_values { -_1 }.select { _2.positive? }
    end

    # Each day's biggest shortfall the till turned away (a cashier trying again isn't more demand), summed.
    def unmet
      @unmet ||= account.stock_refusals.where(branch: branch, created_at: since..)
        .group(:product_id, Arel.sql(local_date("stock_refusals.created_at"))).maximum(Arel.sql("stock_refusals.quantity - GREATEST(stock_refusals.on_hand, 0)"))
        .each_with_object(Hash.new(0)) { |((product_id, _day), short), totals| totals[product_id] += short.to_d if short.to_d.positive? }
    end

    # How much a day's sales vary, from every day of the look-back (quiet days count as nothing sold).
    def deviation(product_id)
      days = daily_sales.fetch(product_id, {})
      return 0 if days.empty?

      values = Array.new(lookback) { |index| days.fetch(index, 0).to_f }
      mean = values.sum / values.size
      Math.sqrt(values.sum { (_1 - mean)**2 } / values.size)
    end

    # { product id => { days ago => quantity } }
    def daily_sales
      @daily_sales ||= StockMovement.where(branch: branch, reason: "sold", created_at: since..)
        .group(:product_id, Arel.sql(local_date("stock_movements.created_at"))).sum(:quantity)
        .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((product_id, day), quantity), by_product|
          by_product[product_id][(today - day.to_date).to_i] = -quantity
        end
    end

    # How the weeks ahead went last year against the year's average, for a product with a year's history here.
    def seasonal_factor(product_id, lead_time)
      ahead = lead_time + ReorderSuggestion::EXTRA_COVER_DAYS
      last_year = year_sales.fetch(product_id, 0).to_d
      window = season_window_sales(ahead).fetch(product_id, 0).to_d
      return 1 unless first_sales.fetch(product_id, Time.current) <= 330.days.ago && last_year.positive? && window >= 5

      (window / (last_year / 365 * ahead)).clamp(SEASON_RANGE.min, SEASON_RANGE.max).round(2)
    end

    def year_sales
      @year_sales ||= sold_between(365.days.ago, Time.current)
    end

    def season_window_sales(ahead)
      (@season_windows ||= {})[ahead] ||= sold_between(365.days.ago, (365 - ahead).days.ago)
    end

    def first_sales
      @first_sales ||= StockMovement.where(branch: branch, reason: "sold").group(:product_id).minimum(:created_at)
    end

    def sold_between(from, to)
      StockMovement.where(branch: branch, reason: "sold", created_at: from..to).group(:product_id).sum(:quantity).transform_values { -_1 }
    end

    # [ days, measured? ]: the supplier's own record once it has enough deliveries, else what's set.
    def lead_time_for(supplier_product)
      if supplier_product && (measured = measured_lead_times[supplier_product.supplier_id])
        [ measured, true ]
      else
        [ supplier_product&.lead_time_days || account.supplier_lead_time_days, false ]
      end
    end

    # { supplier id => days } from orders sent and their first delivery, the middle of the last ones.
    def measured_lead_times
      @measured_lead_times ||= account.purchase_orders.where.not(sent_at: nil).where(sent_at: LEAD_TIME_HISTORY.ago..)
        .joins(:goods_receipts).group(:id, :supplier_id).pluck(:supplier_id, :sent_at, Arel.sql("MIN(goods_receipts.created_at)"))
        .group_by(&:first).filter_map do |supplier_id, orders|
          days = orders.map { |_, sent, arrived| ((arrived - sent) / 1.day).round.clamp(0, 365) }.sort
          [ supplier_id, days[days.size / 2] ] if days.size >= LEAD_TIME_SAMPLES
        end.to_h
    end

    def today = Time.zone.today

    def local_date(column)
      zone = ActiveSupport::TimeZone[account.time_zone].tzinfo.identifier
      "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{ActiveRecord::Base.connection.quote(zone)})::date"
    end
end
