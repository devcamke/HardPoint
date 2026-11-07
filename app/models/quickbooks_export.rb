require "csv"

# A month of the shop's books for its accountant to import into QuickBooks Online, as journal entries
# (QuickBooks won't import invoices where VAT is set up, which every VAT-registered shop has). Each day
# and branch gets balanced entries: sales by how they were paid with output VAT and cost of sales, voids
# and returns reversing them, deposits, customers paying their accounts, supplier bills with input VAT,
# and paying suppliers. Customers and suppliers come as lists to import first, so the names match.
# Amounts are in the shop's currency; bills in another currency use the rate they were entered at.
class QuickbooksExport
  # key => [ what it's for, the QuickBooks account name used unless the shop changes it ]
  ACCOUNTS = {
    "cash" => [ "Cash taken (and foreign notes)", "Cash on hand" ],
    "mobile_money" => [ "M-Pesa", "M-Pesa" ],
    "airtel_money" => [ "Airtel Money", "Airtel Money" ],
    "card" => [ "Card payments", "Card clearing" ],
    "bank" => [ "Bank transfers and cheques", "Bank" ],
    "receivable" => [ "What customers owe", "Accounts Receivable (A/R)" ],
    "payable" => [ "What the shop owes suppliers", "Accounts Payable (A/P)" ],
    "deposits" => [ "Deposits on orders", "Customer Deposits" ],
    "sales" => [ "Sales, ex VAT", "Sales of Product Income" ],
    "vat_output" => [ "VAT on sales", "VAT Output" ],
    "vat_input" => [ "VAT on purchases", "VAT Input" ],
    "cost_of_sales" => [ "Cost of what was sold", "Cost of Goods Sold" ],
    "inventory" => [ "Stock", "Inventory Asset" ],
    "points" => [ "Old loyalty-points payments", "Loyalty Points Redeemed" ]
  }.freeze

  TENDER_ACCOUNTS = { "cash" => "cash", "foreign_cash" => "cash", "mobile_money" => "mobile_money", "airtel_money" => "airtel_money",
                      "card" => "card", "on_account" => "receivable", "deposit" => "deposits", "points" => "points",
                      "bank_transfer" => "bank", "cheque" => "bank" }.freeze
  JOURNAL_HEADERS = [ "Journal No.", "Journal Date", "Account Name", "Debits", "Credits", "Description", "Name" ].freeze
  ROWS_PER_FILE = 990 # QuickBooks takes up to 1,000 rows a file; entries never split across files

  Line = Data.define(:account, :debit, :credit, :description, :name)
  Entry = Data.define(:date, :description, :lines) do
    def debits = lines.sum(&:debit)
    def credits = lines.sum(&:credit)
    def balanced? = debits == credits
  end
  Skipped = Data.define(:date, :what, :amount, :reason)

  attr_reader :account, :month, :skipped

  def self.account_names(account)
    ACCOUNTS.to_h { |key, (_, default)| [ key, account.quickbooks_accounts[key].presence || default ] }
  end

  def initialize(account, month:)
    @account, @month = account, month.beginning_of_month
    @names = self.class.account_names(account)
    @skipped = []
  end

  def entries
    @entries ||= Time.use_zone(account.time_zone) do
      (sales_entries + void_entries + return_entries + deposit_entries + customer_payment_entries +
        supplier_invoice_entries + supplier_payment_entries).select { _1.lines.any? }.sort_by(&:date)
    end
  end

  # [ filename, CSV ] for each file of journal entries, numbered across the month.
  def journal_files
    files, rows, number = [], [], 0
    entries.each do |entry|
      number += 1
      if rows.size + entry.lines.size > ROWS_PER_FILE && rows.any?
        files << rows
        rows = []
      end
      rows += entry.lines.map do |line|
        [ "HP#{month.strftime("%Y%m")}-#{number.to_s.rjust(4, "0")}", entry.date.strftime("%d/%m/%Y"), line.account,
          amount(line.debit), amount(line.credit), line.description || entry.description, line.name ]
      end
    end
    files << rows if rows.any?
    files.each_with_index.map do |file_rows, index|
      [ files.size > 1 ? "journal-#{index + 1}.csv" : "journal.csv", SafeCsv.generate { |csv| csv << JOURNAL_HEADERS; file_rows.each { csv << _1 } } ]
    end
  end

  def customers_csv
    SafeCsv.generate do |csv|
      csv << [ "Name", "Company", "Email", "Phone", "Street", "Tax Reg. No." ]
      customers.each { csv << [ _1.name, _1.name, _1.email, PhoneNumber.display(_1.phone), _1.address, _1.tax_pin ] }
    end
  end

  def suppliers_csv
    SafeCsv.generate do |csv|
      csv << [ "Name", "Company", "Email", "Phone", "Street", "Tax Reg. No.", "Currency" ]
      suppliers.each { csv << [ _1.name, _1.name, _1.email, PhoneNumber.display(_1.phone), _1.address, _1.tax_pin, _1.currency_code ] }
    end
  end

  def skipped_csv
    SafeCsv.generate do |csv|
      csv << [ "Date", "What", "Amount", "Why it's not in the journal" ]
      skipped.each { csv << [ _1.date.strftime("%d/%m/%Y"), _1.what, _1.amount, _1.reason ] }
    end
  end

  def filename = "#{account.subdomain}-quickbooks-#{month.strftime("%Y-%m")}.zip"

  def to_zip
    files = journal_files # builds the entries, and with them the skipped list
    Zip::OutputStream.write_buffer do |zip|
      { "README.txt" => readme, **files.to_h, "customers.csv" => customers_csv, "suppliers.csv" => suppliers_csv }
        .merge(skipped.any? ? { "not-in-the-journal.csv" => skipped_csv } : {})
        .each { |name, content| zip.put_next_entry(name); zip.write(content) }
    end.string
  end

  private
    def period
      Time.use_zone(account.time_zone) { month.beginning_of_day..month.end_of_month.end_of_day }
    end

    def local_date(time) = time.in_time_zone(account.time_zone).to_date
    def amount(cents) = cents.to_i.zero? ? "" : format("%.2f", cents / 100.0)
    def debit(key, cents, name: nil, description: nil) = Line.new(@names.fetch(key), cents, 0, description, name)
    def credit(key, cents, name: nil, description: nil) = Line.new(@names.fetch(key), 0, cents, description, name)

    # A day's sales at a branch, or (sign -1) the same lines reversed for voids.
    def sale_lines_for(sales, sign)
      lines = []
      sales.group_by { [ _1.branch, local_date(sign.positive? ? _1.completed_at : _1.voided_at) ] }.each do |(branch, date), group|
        sound = group.select do |sale|
          paid = sale.payments.sum(&:amount_cents)
          next true if paid == sale.total_cents

          @skipped << Skipped.new(date, "Sale #{sale.receipt_number}", amount(sale.total_cents), "Its payments (#{amount(paid)}) don't add up to its total")
          false
        end
        next if sound.empty?

        entry_lines = []
        sound.flat_map(&:payments).group_by { [ TENDER_ACCOUNTS.fetch(_1.tender, "cash"), (_1.sale.customer&.name if _1.on_account?) ] }
          .each { |(key, name), payments| entry_lines << debit(key, payments.sum(&:amount_cents), name:) }
        net = sound.sum { _1.total_cents - _1.tax_cents }
        tax = sound.sum(&:tax_cents)
        cost = sound.sum { |sale| sale.lines.sum(&:cost_cents) }
        entry_lines << credit("sales", net)
        entry_lines << credit("vat_output", tax) if tax.positive?
        entry_lines += [ debit("cost_of_sales", cost), credit("inventory", cost) ] if cost.positive?
        entry_lines = entry_lines.map { |line| Line.new(line.account, line.credit, line.debit, line.description, line.name) } if sign.negative?

        what = sign.positive? ? "Sales" : "Voided sales"
        lines << Entry.new(date, "#{what} · #{branch.name} · #{sound.size} #{sound.size == 1 ? "receipt" : "receipts"}", entry_lines)
      end
      lines
    end

    def sales_scope
      account.sales.includes(:branch, :lines, payments: { sale: :customer })
    end

    def sales_entries = sale_lines_for(sales_scope.where(status: %w[ completed voided ], completed_at: period).to_a, 1)
    def void_entries = sale_lines_for(sales_scope.voided.where(voided_at: period).where.not(completed_at: nil).to_a, -1)

    def return_entries
      account.sale_returns.where(created_at: period).includes(:branch, sale: :customer, lines: :sale_line).to_a
        .group_by { [ _1.branch, local_date(_1.created_at) ] }.map do |(branch, date), returns|
          lines = returns.group_by { [ TENDER_ACCOUNTS.fetch(_1.refund_method, "cash"), (_1.sale.customer&.name if _1.refund_method == "on_account") ] }
            .map { |(key, name), group| credit(key, group.sum(&:total_cents), name:) }
          lines << debit("sales", returns.sum { _1.total_cents - _1.tax_cents })
          lines << debit("vat_output", returns.sum(&:tax_cents)) if returns.sum(&:tax_cents).positive?
          cost = returns.flat_map(&:lines).select(&:restock).sum { (_1.sale_line.cost_cents * _1.quantity / _1.sale_line.quantity).round }
          lines += [ debit("inventory", cost), credit("cost_of_sales", cost) ] if cost.positive?
          Entry.new(date, "Returns · #{branch.name} · #{returns.map(&:return_number).to_sentence}", lines)
        end
    end

    def deposit_entries
      account.deposits.where(created_at: period).includes(customer_order: :customer).to_a.group_by { local_date(_1.created_at) }.map do |date, deposits|
        lines = deposits.flat_map do |deposit|
          name = deposit.customer_order.customer.name
          [ debit(TENDER_ACCOUNTS.fetch(deposit.tender, "cash"), deposit.amount_cents, name:, description: "Deposit on #{deposit.customer_order.reference}"),
            credit("deposits", deposit.amount_cents, name:, description: "Deposit on #{deposit.customer_order.reference}") ]
        end
        Entry.new(date, "Deposits on orders", lines)
      end
    end

    def customer_payment_entries
      account.customer_payments.where(paid_on: month..month.end_of_month).includes(:customer).to_a.group_by(&:paid_on).map do |date, payments|
        lines = payments.flat_map do |payment|
          description = [ "Payment", payment.reference ].compact.join(" ")
          [ debit(TENDER_ACCOUNTS.fetch(payment.payment_method, "bank"), payment.amount_cents, name: payment.customer.name, description:),
            credit("receivable", payment.amount_cents, name: payment.customer.name, description:) ]
        end
        Entry.new(date, "Customers paying their accounts", lines)
      end
    end

    def supplier_invoice_entries
      account.supplier_invoices.where(invoice_date: month..month.end_of_month).includes(:supplier).to_a.group_by(&:invoice_date).map do |date, invoices|
        lines = invoices.flat_map do |invoice|
          rate = invoice.supplier.foreign? ? invoice.exchange_rate.to_d : 1
          total, tax = (invoice.total_cents * rate).round, (invoice.tax_cents * rate).round
          description = "Bill #{invoice.number}"
          [ debit("inventory", total - tax, description:), (debit("vat_input", tax, description:) if tax.positive?),
            credit("payable", total, name: invoice.supplier.name, description:) ].compact
        end
        Entry.new(date, "Supplier bills", lines)
      end
    end

    # Paying a supplier in another currency has no rate of its own to convert at, so it's listed for the
    # accountant to enter rather than guessed.
    def supplier_payment_entries
      payments = account.supplier_payments.where(paid_on: month..month.end_of_month).includes(:supplier).to_a
      foreign, local = payments.partition { _1.supplier.foreign? }
      foreign.each do |payment|
        @skipped << Skipped.new(payment.paid_on, "Payment to #{payment.supplier.name}", "#{payment.supplier.currency_code} #{amount(payment.amount_cents)}",
          "Paid in #{payment.supplier.currency_code}; enter it at the rate your bank used")
      end
      local.group_by(&:paid_on).map do |date, group|
        lines = group.flat_map do |payment|
          description = [ "Payment", payment.reference ].compact.join(" ")
          [ debit("payable", payment.amount_cents, name: payment.supplier.name, description:),
            credit(TENDER_ACCOUNTS.fetch(payment.payment_method, "bank"), payment.amount_cents, description:) ]
        end
        Entry.new(date, "Paying suppliers", lines)
      end
    end

    def customers
      ids = entries.flat_map(&:lines).filter_map(&:name).uniq
      account.customers.where(name: ids).order(:name)
    end

    def suppliers
      names = entries.flat_map(&:lines).filter_map(&:name).uniq
      account.suppliers.where(name: names).order(:name)
    end

    def readme
      <<~TEXT
        #{account.name}: books for #{month.strftime("%B %Y")} from HardPoint, for QuickBooks Online.

        Import in this order (QuickBooks: Settings > Import data):
          1. customers.csv as Customers and suppliers.csv as Suppliers, so every name in the journal exists.
          2. #{journal_files.map(&:first).join(", ")} as Journal entries. Dates are day/month/year (choose
             dd/MM/yyyy when mapping). Each entry balances; QuickBooks takes up to 1,000 rows a file.

        Accounts used (change them in HardPoint > Reports > QuickBooks export to match your chart of accounts):
        #{@names.map { |key, name| "  #{ACCOUNTS.fetch(key).first}: #{name}" }.join("\n")}

        Amounts are in #{account.currency}. Supplier bills in another currency are converted at the rate they were
        entered at. #{skipped.any? ? "not-in-the-journal.csv lists what couldn't go in the journal and why." : "Everything for the month is in the journal."}
      TEXT
    end
end
