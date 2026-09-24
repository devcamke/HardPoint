# A report: one or more sections (tables) for a period and, optionally, a branch. Reports are
# plain SQL aggregates over the shop's own rows (row-level security applies as everywhere),
# rendered as HTML and exported as CSV or PDF.
class Report
  Column = Data.define(:label, :type) do
    def numeric? = type != :text && type != :date && type != :link
  end

  Section = Data.define(:title, :columns, :rows, :totals, :note, :emphasis) do
    def initialize(columns:, rows:, title: nil, totals: nil, note: nil, emphasis: [])
      super
    end
  end

  # A cell that links to a record on screen; exports use the text.
  Link = Data.define(:text, :record) do
    def to_s = text.to_s
  end

  # The share of a line's price actually paid once the cart discount is spread over the lines.
  PAID_SHARE = "(CASE WHEN sales.subtotal_cents = 0 THEN 0 ELSE sales.total_cents::numeric / sales.subtotal_cents END)".freeze

  # Periods up to this long list every day, even quiet ones.
  FILL_DAYS = 62

  KEYS = %w[ sales profit_and_loss tax payments discounts_and_voids stock_valuation dead_stock shifts ].freeze

  class_attribute :title, :description, :group, :uses_period, default: true

  def self.find(key)
    "Report::#{key.to_s.camelize}".constantize if key.to_s.in?(KEYS)
  end

  def self.key
    name.demodulize.underscore
  end

  # Extra choices a report takes, e.g. how to group sales: [ name, label, choices or :number, default ]
  def self.options
    []
  end

  attr_reader :account, :period, :branch, :options

  def initialize(account:, period:, branch: nil, options: {})
    @account = account
    @period = period
    @branch = branch
    @options = self.class.options.to_h { |name, _, _, default| [ name, options[name].presence || default ] }
  end

  def sections
    raise NotImplementedError
  end

  def subtitle
    [ (period.label if uses_period), (branch&.name || "All branches") ].compact.join(" · ")
  end

  def to_csv
    CSV.generate do |csv|
      csv << [ "#{account.name}: #{title}", subtitle ]
      sections.each do |section|
        csv << []
        csv << [ section.title ] if section.title
        csv << section.columns.map(&:label)
        section.rows.each { |row| csv << row.zip(section.columns).map { |value, column| export(value, column) } }
        csv << section.totals.zip(section.columns).map { |value, column| export(value, column) } if section.totals
      end
    end
  end

  def filename(extension)
    [ self.class.key.dasherize, (period.from.iso8601 if uses_period), (period.to.iso8601 if uses_period), branch&.code&.downcase ].compact.join("-") + ".#{extension}"
  end

  private
    def export(value, column)
      case column.type
      when :money then value.is_a?(Numeric) ? format("%.2f", value / 100.0) : value
      when :percent then value&.round(1)
      when :quantity then value&.to_d&.to_s("F")&.delete_suffix(".0")
      else value.to_s
      end
    end

    def money(...) = Money.format(...)

    def completed_sales
      scope = account.sales.completed.where(completed_at: period.range)
      branch ? scope.where(branch: branch) : scope
    end

    def returns
      scope = account.sale_returns.where(created_at: period.range)
      branch ? scope.where(branch: branch) : scope
    end

    # Lines of the period's sales. Filtering by a subquery of sales (rather than joining and
    # filtering) keeps Postgres on the sales index; the row-level security policy makes it
    # misjudge how many rows a plain join would find.
    def sold_lines
      SaleLine.where(sale_id: completed_sales.select(:id)).joins(:sale)
    end

    def returned_lines
      SaleReturnLine.where(sale_return_id: returns.select(:id)).joins(:sale_return, sale_line: :sale)
    end

    # The local date of a UTC timestamp column, in the shop's time zone.
    def local_date(column)
      "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{ActiveRecord::Base.connection.quote(time_zone)})::date"
    end

    def time_zone
      ActiveSupport::TimeZone[account.time_zone].tzinfo.identifier
    end

    def percent(part, whole)
      whole.to_i.zero? ? nil : (part * 100.0 / whole)
    end
end
