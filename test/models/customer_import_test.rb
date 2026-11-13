require "test_helper"

class CustomerImportTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @shift = shifts(:acme_front_open)
    @existing = customers(:acme_contractor) # Mwangi Builders Ltd, +254722000111, 30 days' terms
  end

  def import(csv)
    CustomerImport.new(account: Current.account, creator: users(:amina), csv: csv, filename: "debtors.csv")
  end

  test "new customers come in with what they owe as an opening balance" do
    import = import(<<~CSV)
      name,phone,credit_limit,payment_terms_days,balance,balance_date
      Otieno Fundi,0711 222 333,"KES 100,000",14,"45,500.50",01/10/2026
      Achieng Stores,,,,,
    CSV

    travel_to Date.new(2026, 11, 13) do
      assert_difference -> { Current.account.customers.count }, 2 do
        assert import.save, import.errors.full_messages.to_sentence + import.problems.inspect
      end
      assert_equal [ 2, 0, 1, 45_500_50 ], [ import.created_count, import.updated_count, import.balances_count, import.balances_cents ]

      otieno = Current.account.customers.find_by!(name: "Otieno Fundi")
      assert_equal [ "0711222333", 100_000_00, 14, 45_500_50 ], [ otieno.phone, otieno.credit_limit_cents, otieno.payment_terms_days, otieno.balance_cents ]
      assert_equal [ [ "Opening balance", 45_500_50, Date.new(2026, 10, 15), 45_500_50 ] ],
        otieno.open_invoices.map { [ _1.reference, _1.amount_cents, _1.due_date, _1.outstanding_cents ] }
      assert_equal 45_500_50, otieno.ageing["1_30"], "due 14 days after 1 October, so 29 days late"
      assert_equal otieno.ageing, Customer.ageing_by_id([ otieno ])[otieno.id]
      assert_equal [ [ otieno, 45_500_50 ] ], Current.account.customers.with_balances
      assert_equal 0, Current.account.customers.find_by!(name: "Achieng Stores").balance_cents
    end
    assert_equal "customers_imported", Current.account.events.order(:id).last.action
  end

  test "payments settle the opening balance first, and it shows on the statement" do
    assert import("name,phone,balance,balance_date\nOtieno Fundi,0711222333,10000,2026-10-01\n").save
    otieno = Current.account.customers.find_by!(name: "Otieno Fundi")

    otieno.customer_payments.create!(account: Current.account, amount_cents: 4_000_00, payment_method: "bank_transfer", paid_on: Date.new(2026, 10, 20))
    assert_equal 6_000_00, otieno.balance_cents
    assert_equal [ [ "Opening balance", 6_000_00 ] ], otieno.open_invoices.map { [ _1.reference, _1.outstanding_cents ] }

    statement = otieno.statement(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))
    assert_equal [ [ "Opening balance, brought across", 10_000_00, 0, 10_000_00 ], [ "Payment, bank transfer", 0, 4_000_00, 6_000_00 ] ],
      statement.entries.map { [ _1.description, _1.charge_cents, _1.credit_cents, _1.balance_cents ] }
    assert_equal 6_000_00, statement.ageing.values.sum, "the ageing adds up to the closing balance"

    otieno.customer_payments.create!(account: Current.account, amount_cents: 6_000_00, payment_method: "bank_transfer")
    assert_empty otieno.open_invoices
    assert_equal 0, otieno.balance_cents
  end

  test "a line that matches a customer already here updates them; a balance isn't added on top of an account in use" do
    @existing.customer_payments.create!(account: Current.account, amount_cents: 1_000_00, payment_method: "bank_transfer")
    import = import("name,phone,credit_limit,balance\nMwangi Builders,0722 000 111,80000,25000\nGrace Wambui,,,3000\n")

    assert_no_difference -> { Current.account.customers.count } do
      assert import.save, import.problems.inspect
    end
    assert_equal [ 0, 1, 1 ], [ import.created_count, import.updated_count, import.balances_count ], "Grace only gained a balance"
    assert_equal [ "Mwangi Builders", 80_000_00, -1_000_00 ], [ @existing.reload.name, @existing.credit_limit_cents, @existing.balance_cents ]
    assert_match "already has entries on their account", import.passed_over.sole.messages.sole
    assert_equal 3_000_00, customers(:acme_walk_in).balance_cents, "matched by name, with nothing on the account yet"

    again = import("name,balance\nGrace Wambui,3000\n")
    assert again.save
    assert_equal 3_000_00, customers(:acme_walk_in).balance_cents, "importing the same file twice doesn't double the debt"
  end

  test "any problem stops the whole file, and says which line" do
    import = import(<<~CSV)
      name,phone,email,credit_limit,balance,balance_date
      Good Customer,0700111222,,1000,500,
      ,0700333444,,,,
      Bad Amount,0700555666,not-an-email,lots,a few,31/02/2026
      Good Customer Again,0700 111 222,,,,
    CSV

    assert_no_difference -> { Current.account.customers.count } do
      assert_not import.save
    end
    assert_equal [ 3, 4, 5 ], import.problems.map(&:line)
    assert_match "Name can't be blank", import.problems[0].messages.to_sentence
    bad = import.problems[1].messages.to_sentence
    assert_match "credit_limit “lots” isn't an amount", bad
    assert_match "balance “a few” isn't an amount", bad
    assert_match "balance_date “31/02/2026” isn't a date", bad
    assert_match "Email is invalid", bad
    assert_match "is the same customer as line 2", import.problems[2].messages.to_sentence
  end

  test "a customer in credit comes across with a minus: the credit settles what they buy next, and can be refunded" do
    assert import("name,phone,credit_limit,balance\nOtieno Fundi,0711222333,50000,-2500\n").save
    otieno = Current.account.customers.find_by!(name: "Otieno Fundi")

    assert_equal(-2_500_00, otieno.balance_cents)
    assert_empty otieno.open_invoices
    assert_equal [ [ "Credit brought across", 0, 2_500_00 ] ], otieno.statement.entries.map { [ _1.description, _1.charge_cents, _1.credit_cents ] }
    assert_equal 52_500_00, otieno.available_credit_cents
    refund = otieno.customer_payments.new(account: Current.account, kind: "refund", amount_cents: 2_500_00, payment_method: "bank_transfer")
    assert refund.valid?, refund.errors.full_messages.to_sentence
  end

  test "a file without a name column, or with nothing in it, is refused" do
    assert_not import("phone,balance\n0700111222,500\n").save
    assert_not import("").save
  end

  test "an opening balance isn't money taken: it stays out of the shift and goes to QuickBooks as a debt brought across" do
    assert import("name,balance,balance_date\nOtieno Fundi,10000,#{Date.current.beginning_of_month.iso8601}\n").save
    entry = Current.account.customer_payments.opening_balances.sole

    assert_equal [ -10_000_00, nil, nil ], [ entry.amount_cents, entry.payment_method, entry.shift_id ]
    assert_empty Current.account.customer_payments.money
    assert_not entry.customer.customer_payments.new(account: Current.account, kind: "opening_balance", amount_cents: -500_00).valid?, "one opening balance a customer"

    lines = QuickbooksExport.new(Current.account, month: Date.current.beginning_of_month).send(:customer_payment_entries).flat_map(&:lines)
    assert_equal 2, lines.size
    assert_equal [ 10_000_00 ], lines.map { _1.to_h.values.grep(Integer).max }.uniq
  end
end
