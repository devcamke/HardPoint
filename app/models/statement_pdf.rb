# A customer's statement: brought forward, the period's sales, credits and payments with a running
# balance, and what's overdue.
class StatementPdf < DocumentPdf
  COLUMNS = [ [ "Date", 70 ], [ "Details", 115 ], [ "Reference", 90 ], [ "Charges", 75 ], [ "Credits", 75 ], [ "Balance", 90 ] ].freeze
  BUCKET_LABELS = { "current" => "Not yet due", "1_30" => "1–30 days", "31_60" => "31–60 days", "61_90" => "61–90 days", "over_90" => "Over 90 days" }.freeze

  def initialize(statement, branch:)
    @statement = statement
    super(account: statement.customer.account, branch: branch)
  end

  def title = "Statement"
  def reference = @statement.customer.name
  def filename = @statement.filename

  private
    def details
      [ "#{date(@statement.from)} to #{date(@statement.to)}", "Payment terms #{@statement.customer.payment_terms_days} days" ]
    end

    def content
      customer = @statement.customer
      two_blocks "Account", [ customer.name, customer.phone, customer.email, customer.address, ("PIN #{customer.tax_pin}" if customer.tax_pin.present?) ],
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      rows = [ [ short_date(@statement.from), "Brought forward", "", "", "", money(@statement.opening_balance_cents) ] ]
      rows += @statement.entries.map do |entry|
        [ short_date(entry.date), entry.description, entry.reference, (money(entry.charge_cents) if entry.charge_cents.positive?),
          (money(entry.credit_cents) if entry.credit_cents.positive?), money(entry.balance_cents) ]
      end
      table rows
      total "Balance due", @statement.closing_balance_cents

      pdf.move_down 16
      ageing = @statement.ageing
      ageing_columns = BUCKET_LABELS.map { |_, label| [ label, WIDTH / 5 ] }
      with_columns(ageing_columns, numeric_from: 0) do
        row BUCKET_LABELS.values, bold: true, fill: CONCRETE
        row BUCKET_LABELS.keys.map { money(ageing[_1]) }
      end

      pdf.move_down 16
      note "Please pay by M-Pesa, bank transfer or at the counter, quoting your name. Thank you for your business."
    end

    def short_date(value)
      value.strftime("%-d %b %Y")
    end

    def with_columns(columns, numeric_from:)
      @columns, @numeric_from = columns, numeric_from
      yield
    ensure
      @columns = @numeric_from = nil
    end

    def columns = @columns || COLUMNS
    def numeric_from = @numeric_from || 3
end
