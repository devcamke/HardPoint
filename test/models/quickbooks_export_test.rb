require "test_helper"

class QuickbooksExportTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
  end

  def sell(customer: nil, tender: "cash", products: [ :acme_nails ])
    @shift.current_sale.tap do |sale|
      sale.change_customer(customer) if customer
      products.each { sale.add(products(_1)) }
      sale.pay(tender: tender)
    end
  end

  def export = QuickbooksExport.new(@account, month: Date.current)

  def lines_of(entry) = entry.lines.map { [ _1.account, _1.debit, _1.credit, _1.name ] }

  test "a day's sales: each way of paying debited, sales ex VAT and VAT credited, with cost of sales" do
    cash = sell
    on_account = sell(customer: customers(:acme_contractor), tender: "on_account")

    entry = export.entries.find { _1.description.start_with?("Sales") }
    assert entry.balanced?
    assert_includes lines_of(entry), [ "Cash on hand", cash.total_cents, 0, nil ]
    assert_includes lines_of(entry), [ "Accounts Receivable (A/R)", on_account.total_cents, 0, "Mwangi Builders Ltd" ]
    assert_includes lines_of(entry), [ "Sales of Product Income", 0, cash.total_cents + on_account.total_cents - cash.tax_cents - on_account.tax_cents, nil ]
    assert_includes lines_of(entry), [ "VAT Output", 0, cash.tax_cents + on_account.tax_cents, nil ]
    assert_includes lines_of(entry), [ "Cost of Goods Sold", (cash.lines + on_account.lines).sum(&:cost_cents), 0, nil ]
  end

  test "voids, returns, deposits, account payments, supplier bills and payments each balance" do
    sell.void(reason: "Rang up twice", by: users(:amina))
    kept = sell(products: %i[ acme_nails acme_nails ])
    @account.sale_returns.create!(sale: kept, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: kept.lines.sole, quantity: 1, restock: true } ])
    order = @account.customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
      lines_attributes: [ { account: @account, product_code: "CEM-50", quantity: 1 } ]).tap(&:confirm)
    order.take_deposit(amount_cents: 200_00, tender: "mobile_money", reference: "SKX1", shift: @shift)
    @account.customer_payments.create!(customer: customers(:acme_contractor), amount_cents: 5000_00, payment_method: "bank_transfer", paid_on: Date.current)
    @account.supplier_invoices.create!(supplier: suppliers(:acme_cement_distributor), number: "INV-77", invoice_date: Date.current,
      due_date: Date.current + 30, total_cents: 11600_00, tax_cents: 1600_00)
    @account.supplier_payments.create!(supplier: suppliers(:acme_cement_distributor), amount_cents: 11600_00, payment_method: "mobile_money", paid_on: Date.current)

    entries = export.entries
    assert entries.all?(&:balanced?), entries.reject(&:balanced?).map(&:description).to_sentence
    descriptions = entries.map(&:description)
    %w[ Sales Voided Returns Deposits Customers Supplier Paying ].each { |start| assert descriptions.any? { _1.start_with?(start) }, start }

    bill = entries.find { _1.description == "Supplier bills" }
    assert_equal [ [ "Inventory Asset", 10000_00, 0, nil ], [ "VAT Input", 1600_00, 0, nil ], [ "Accounts Payable (A/P)", 0, 11600_00, "Nairobi Cement Distributors" ] ], lines_of(bill)
    assert_includes lines_of(entries.find { _1.description == "Paying suppliers" }), [ "M-Pesa", 0, 11600_00, nil ]
  end

  test "the shop's own account names are used, and paying a supplier in dollars is listed rather than guessed" do
    @account.update!(quickbooks_accounts: { "cash" => "Till cash", "mobile_money" => "Safaricom M-Pesa" })
    @account.currencies.create!(code: "USD", rate: 130)
    importer = @account.suppliers.create!(name: "Guangzhou Tools", currency: "USD")
    @account.supplier_payments.create!(supplier: importer, amount_cents: 500_00, payment_method: "bank_transfer", paid_on: Date.current)
    sell

    export = self.export
    assert export.entries.first.lines.any? { _1.account == "Till cash" }
    assert_equal [ "Payment to Guangzhou Tools" ], export.skipped.map(&:what)
  end

  test "the download: journal in QuickBooks' columns, customers and suppliers to import first, and a README" do
    sell(customer: customers(:acme_contractor), tender: "on_account")
    export = self.export

    names = []
    Zip::InputStream.open(StringIO.new(export.to_zip)) { |zip| while (entry = zip.get_next_entry) do names << entry.name end }
    assert_equal %w[ README.txt journal.csv customers.csv suppliers.csv ], names

    journal = CSV.parse(export.journal_files.first.last, headers: true)
    assert_equal QuickbooksExport::JOURNAL_HEADERS, journal.headers
    assert_match(%r{\A\d{2}/\d{2}/\d{4}\z}, journal.first["Journal Date"])
    assert_equal journal.sum { _1["Debits"].to_d }, journal.sum { _1["Credits"].to_d }
    assert_includes export.customers_csv, "Mwangi Builders Ltd"
  end

  test "a big month is split into files under QuickBooks' 1,000-row limit without splitting an entry" do
    stub_const(QuickbooksExport, :ROWS_PER_FILE, 6) do
      sell
      @account.customer_payments.create!(customer: customers(:acme_contractor), amount_cents: 100_00, payment_method: "bank_transfer", paid_on: Date.current)
      files = export.journal_files
      assert_equal %w[ journal-1.csv journal-2.csv ], files.map(&:first)
      assert files.all? { |_, csv| CSV.parse(csv).size - 1 <= 6 }
    end
  end

  private
    def stub_const(owner, name, value)
      original = owner.const_get(name)
      owner.send(:remove_const, name)
      owner.const_set(name, value)
      yield
    ensure
      owner.send(:remove_const, name)
      owner.const_set(name, original)
    end
end
