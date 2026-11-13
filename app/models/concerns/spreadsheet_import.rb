# The shared part of bringing people across from a spreadsheet (CustomerImport, SupplierImport): read the CSV,
# check every line, and save them all or none. The whole file is checked first and nothing is saved while any
# line has a problem, so a shop never ends up with half a list in.
#
# Includers define COLUMNS, #build_rows (an array of rows, calling #problem for each line that won't do),
# #import(row) and #imported_event (the name of the Activity entry).
module SpreadsheetImport
  extend ActiveSupport::Concern

  MAX_SIZE = 2.megabytes
  MAX_ROWS = 5_000
  MAX_PROBLEMS = 100

  Problem = Data.define(:line, :messages)

  included do
    include ActiveModel::Model

    attr_accessor :account, :csv, :filename, :creator
    attr_reader :problems, :passed_over, :created_count, :updated_count, :balances_count, :balances_cents

    validates :csv, presence: { message: "file is missing or empty" }
    validates :csv, length: { maximum: MAX_SIZE, message: "file is too big (2 MB at most)" }
    validate :readable_with_a_name_column
  end

  def initialize(...)
    super
    @problems, @passed_over = [], []
    @created_count = @updated_count = @balances_count = @balances_cents = 0
  end

  # Checks every line, then saves them all or none. False with #errors or #problems saying why.
  def save
    return false unless valid?

    rows = build_rows
    return false if problems.any?

    ActiveRecord::Base.transaction do
      rows.each { import _1 }
      account.track_event imported_event, creator: creator, created: created_count, updated: updated_count,
        balances: balances_count, owed: balances_cents, file: filename
    end
    true
  end

  def more_problems? = @problem_count.to_i > problems.size

  private
    def table
      @table ||= CSV.parse(csv, headers: true, header_converters: ->(header) { header.to_s.strip.downcase.tr(" ", "_") },
        converters: [ SafeCsv::UNESCAPE ], skip_blanks: true)
    end

    # Each line with something on it, with its line number in the spreadsheet (the column names are line 1).
    def lines
      table.each.with_index(2).reject { |data, _| data.to_h.values.all?(&:blank?) }
    end

    def readable_with_a_name_column
      return if csv.blank? || csv.length > MAX_SIZE

      errors.add :csv, "needs a “name” column (see the template)" unless table.headers.include?("name")
      errors.add :csv, "has more than #{MAX_ROWS.to_fs(:delimited)} lines; split it into smaller files" if table.size > MAX_ROWS
    rescue CSV::MalformedCSVError => error
      errors.add :csv, "couldn't be read: #{error.message}"
    end

    def problem(line, messages)
      @problem_count = @problem_count.to_i + 1
      problems << Problem.new(line, messages) if problems.size < MAX_PROBLEMS
    end

    def pass_over(line, message)
      passed_over << Problem.new(line, [ message ])
    end

    # [ cents, date ] for a line's balance and balance_date, or nil when there's no balance; anything wrong
    # with either goes on messages. Negative amounts (a credit) are the includer's to allow or refuse.
    def balance_for(data, messages)
      return if data["balance"].blank?

      cents = Monetary.to_cents(clean_number(data["balance"]))
      messages << "balance “#{data["balance"]}” isn't an amount" if cents.nil?

      date = data["balance_date"].present? ? parse_date(data["balance_date"]) : Date.current
      if date.nil?
        messages << "balance_date “#{data["balance_date"]}” isn't a date; write it like #{Date.current.iso8601} or #{Date.current.strftime("%d/%m/%Y")}"
      elsif date > Date.current
        messages << "balance_date #{data["balance_date"]} is in the future"
      end
      [ cents, date ] if cents && cents.nonzero? && date
    end

    def days_for(data, messages)
      return if data["payment_terms_days"].blank?

      days = Integer(data["payment_terms_days"].to_s.strip, 10, exception: false)
      messages << "payment_terms_days “#{data["payment_terms_days"]}” isn't a number of days" unless days && days >= 0
      days if days && days >= 0
    end

    # Amounts as people type them: "KES 12,500", "12 500.00", "Ksh. 1,200/=".
    def clean_number(value)
      value.to_s.gsub(/\A\s*(kes|kshs|ksh|sh)\.?\s*/i, "").delete(" ").sub(%r{/[=-]\z}, "")
    end

    # 2026-11-13, or the day first as it's written in Kenya: 13/11/2026, 13-11-2026, 13.11.26.
    def parse_date(value)
      text = value.to_s.strip
      if (iso = text.match(/\A(\d{4})-(\d{1,2})-(\d{1,2})\z/))
        Date.new(iso[1].to_i, iso[2].to_i, iso[3].to_i)
      elsif (local = text.match(%r{\A(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2}|\d{4})\z}))
        Date.new(local[3].length == 2 ? 2000 + local[3].to_i : local[3].to_i, local[2].to_i, local[1].to_i)
      end
    rescue Date::Error
      nil
    end

    def last_nine(phone)
      digits = phone.to_s.gsub(/\D/, "")
      digits.last(9) if digits.length >= 9
    end
end
