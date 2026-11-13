require "test_helper"

class SupplierImportTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
  end

  def import(csv)
    SupplierImport.new(account: Current.account, creator: users(:amina), csv: csv, filename: "creditors.csv")
  end

  test "new suppliers come in with what the shop owes them as an opening invoice" do
    import = import(<<~CSV)
      name,contact_name,phone,payment_terms_days,balance,balance_date
      Steel Masters Ltd,Joseph Kariuki,0733 444 555,14,"KES 62,500",01/10/2026
      Rift Valley Paints,,,,,
    CSV

    travel_to Date.new(2026, 11, 13) do
      assert_difference -> { Current.account.suppliers.count }, 2 do
        assert import.save, import.errors.full_messages.to_sentence + import.problems.inspect
      end
      assert_equal [ 2, 0, 1, 62_500_00 ], [ import.created_count, import.updated_count, import.balances_count, import.balances_cents ]

      steel = Current.account.suppliers.find_by!(name: "Steel Masters Ltd")
      assert_equal [ "Joseph Kariuki", "0733444555", 14, 62_500_00 ], [ steel.contact_name, steel.phone, steel.payment_terms_days, steel.balance_cents ]
      invoice = steel.supplier_invoices.sole
      assert_equal [ "OPENING BALANCE", true, Date.new(2026, 10, 1), Date.new(2026, 10, 15), 0 ],
        [ invoice.number, invoice.opening_balance, invoice.invoice_date, invoice.due_date, invoice.tax_cents ]
      assert_equal 62_500_00, steel.ageing["1_30"]
      assert_equal 0, Current.account.suppliers.find_by!(name: "Rift Valley Paints").balance_cents

      steel.supplier_payments.create!(account: Current.account, amount_cents: 22_500_00, payment_method: "bank_transfer", paid_on: Date.current)
      assert_equal [ 40_000_00 ], steel.open_invoices.map(&:outstanding_cents), "payments settle it like any invoice"
    end
    assert_equal "suppliers_imported", Current.account.events.order(:id).last.action
  end

  test "it isn't a purchase: it stays out of the VAT report and goes to QuickBooks as a debt brought across" do
    assert import("name,balance\nSteel Masters Ltd,10000\n").save

    lines = QuickbooksExport.new(Current.account, month: Date.current).send(:supplier_invoice_entries).flat_map(&:lines).select { _1.description == "Opening balance" }
    names = QuickbooksExport.account_names(Current.account)
    assert_equal [ [ names["opening_balances"], 10_000_00, 0 ], [ names["payable"], 0, 10_000_00 ] ], lines.map { [ _1.account, _1.debit, _1.credit ] }

    tax = Report::Tax.new(account: Current.account, period: Report::Period.for_preset("today"))
    assert_equal 0, tax.send(:input_rows).first[1], "no purchases in the VAT report"
  end

  test "a line that matches a supplier already here updates them; a balance isn't added for one already trading" do
    known = Current.account.suppliers.create!(name: "Bamburi Depot")
    known.supplier_payments.create!(account: Current.account, amount_cents: 1_000_00, payment_method: "bank_transfer", paid_on: Date.current)

    import = import("name,phone,balance\nbamburi depot,0722 111 222,5000\n")
    assert_no_difference -> { Current.account.suppliers.count } do
      assert import.save, import.problems.inspect
    end
    assert_equal [ 0, 1, 0 ], [ import.created_count, import.updated_count, import.balances_count ]
    assert_equal [ "0722111222", -1_000_00 ], [ known.reload.phone, known.balance_cents ]
    assert_match "already has orders, invoices or payments", import.passed_over.sole.messages.sole
  end

  test "any problem stops the whole file, and says which line" do
    import = import(<<~CSV)
      name,email,balance,balance_date
      Good Supplier,,500,
      ,,,01/01/2026
      Owes Us,,-200,
      Bad Lines,not-an-email,lots,31/02/2026
      good supplier,,,
    CSV

    assert_no_difference -> { Current.account.suppliers.count } do
      assert_not import.save
    end
    assert_equal [ 3, 4, 5, 6 ], import.problems.map(&:line)
    assert_match "Name can't be blank", import.problems[0].messages.to_sentence
    assert_match "money the supplier owes you", import.problems[1].messages.to_sentence
    assert_match "balance “lots” isn't an amount", import.problems[2].messages.to_sentence
    assert_match "is the same supplier as line 2", import.problems[3].messages.to_sentence
  end
end
