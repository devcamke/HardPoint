# The dates a report covers, in the shop's time zone: a preset like "this month" or any range.
class Report::Period
  PRESETS = {
    "today" => "Today", "yesterday" => "Yesterday", "this_week" => "This week", "last_week" => "Last week",
    "this_month" => "This month", "last_month" => "Last month", "last_30_days" => "Last 30 days", "this_year" => "This year"
  }.freeze

  attr_reader :from, :to, :preset

  def self.from_params(params, default: "this_month")
    preset = params[:preset].presence_in(PRESETS.keys)
    from = Date.parse(params[:from].to_s) rescue nil
    to = Date.parse(params[:to].to_s) rescue nil

    if preset || from.nil? || to.nil?
      for_preset(preset || default)
    else
      new(from: [ from, to ].min, to: [ from, to ].max)
    end
  end

  def self.for_preset(preset, today: Time.zone.today)
    from, to = case preset
    when "today" then [ today, today ]
    when "yesterday" then [ today - 1, today - 1 ]
    when "this_week" then [ today.beginning_of_week, today ]
    when "last_week" then [ (today - 7).beginning_of_week, (today - 7).end_of_week ]
    when "last_month" then [ today.prev_month.beginning_of_month, today.prev_month.end_of_month ]
    when "last_30_days" then [ today - 29, today ]
    when "this_year" then [ today.beginning_of_year, today ]
    else [ today.beginning_of_month, today ]
    end
    new(from: from, to: to, preset: preset)
  end

  def initialize(from:, to:, preset: nil)
    @from = from
    @to = to
    @preset = preset
  end

  def range
    from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
  end

  def dates
    from..to
  end

  def days
    (to - from).to_i + 1
  end

  def label
    dates = from == to ? from.to_fs(:long) : "#{from.to_fs(:long)} – #{to.to_fs(:long)}"
    preset && preset != "custom" ? "#{PRESETS[preset]} (#{dates})" : dates
  end

  def to_param
    preset ? { preset: preset } : { from: from.iso8601, to: to.iso8601 }
  end
end
