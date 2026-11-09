require "test_helper"

class CustomerAccountTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @customer = customers(:acme_contractor) # 50,000.00 credit limit, 30 days' terms
  end

  def account_sale(quantity:, days_ago: 0, approver: nil)
    sale = @shift.current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_nails), quantity: quantity) # 250.00 a kg
    payment = sale.pay(tender: "on_account", credit_approver: approver)
    assert payment.persisted?, payment.errors.full_messages.to_sentence
    sale.update_columns(completed_at: days_ago.days.ago)
    sale
  end

  test "account sales are invoices; payments settle the oldest first" do
    old = account_sale(quantity: 40, days_ago: 45) # 10,000.00, 15 days late
    recent = account_sale(quantity: 20, days_ago: 5) # 5,000.00, not yet due

    assert_equal 15_000_00, @customer.balance_cents
    assert_equal({ "current" => 5_000_00, "1_30" => 10_000_00, "31_60" => 0, "61_90" => 0, "over_90" => 0 }, @customer.ageing)
    assert_equal 10_000_00, @customer.overdue_cents
    assert_equal [ [ @customer, 15_000_00 ] ], Current.account.customers.with_balances, "lists work it out for everyone at once"
    assert_equal @customer.ageing, Customer.ageing_by_id([ @customer ])[@customer.id]

    @customer.customer_payments.create!(account: Current.account, amount_cents: 12_000_00, payment_method: "bank_transfer")

    assert_equal 3_000_00, @customer.balance_cents
    assert_equal [ [ recent, 3_000_00 ] ], @customer.open_invoices.map { [ _1.sale, _1.outstanding_cents ] }
    assert_equal 0, @customer.overdue_cents
    assert_equal({ @customer.id => 3_000_00 }, Customer.balances_by_id([ @customer.id ]))
    assert_equal @customer.ageing, Customer.ageing_by_id([ @customer ])[@customer.id]
    assert_equal old.completed_at.to_date + 30, @customer.due_date_for(old)
  end

  test "going over the credit limit needs an owner's or manager's approval" do
    account_sale(quantity: 160) # 40,000.00 of 50,000.00

    sale = @shift.current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_nails), quantity: 60) # 15,000.00
    refused = sale.pay(tender: "on_account")
    assert_match "only KES 10,000.00 of credit left", refused.errors.full_messages.to_sentence
    assert sale.reload.open?

    assert sale.pay(tender: "on_account", credit_approver: users(:amina)).persisted?
    assert sale.reload.completed?
    assert_equal users(:amina), sale.credit_approver
    assert_equal "credit_approved", sale.events.last.action
    assert_equal 55_000_00, @customer.balance_cents
  end

  test "the statement brings the balance forward and runs it through the period" do
    account_sale(quantity: 40, days_ago: 45)
    account_sale(quantity: 20, days_ago: 5)
    @customer.customer_payments.create!(account: Current.account, amount_cents: 4_000_00, payment_method: "mobile_money",
      reference: "SJK4H7T2QP", paid_on: 3.days.ago.to_date)

    statement = @customer.statement(from: 10.days.ago.to_date, to: Date.current)

    assert_equal 10_000_00, statement.opening_balance_cents
    assert_equal [ [ 5_000_00, 0, 15_000_00 ], [ 0, 4_000_00, 11_000_00 ] ], statement.entries.map { [ _1.charge_cents, _1.credit_cents, _1.balance_cents ] }
    assert_equal 11_000_00, statement.closing_balance_cents
    assert StatementPdf.new(statement, branch: branches(:acme_main)).render.start_with?("%PDF")
  end

  test "a payment can be put against particular sales; the rest settles the oldest first" do
    old = account_sale(quantity: 40, days_ago: 45) # 10,000.00
    recent = account_sale(quantity: 20, days_ago: 5) # 5,000.00

    too_much = @customer.customer_payments.create(account: Current.account, amount_cents: 2_000_00, payment_method: "bank_transfer",
      allocations_attributes: [ { sale: recent, amount_cents: 3_000_00 } ])
    assert_match "more than the KES 2,000.00 paid", too_much.errors.full_messages.to_sentence

    over_the_sale = @customer.customer_payments.create(account: Current.account, amount_cents: 8_000_00, payment_method: "bank_transfer",
      allocations_attributes: [ { sale: recent, amount_cents: 6_000_00 } ])
    assert_match "only KES 5,000.00 is owed on #{recent.receipt_number}", over_the_sale.errors.full_messages.to_sentence

    @customer.customer_payments.create!(account: Current.account, amount_cents: 5_000_00, payment_method: "bank_transfer",
      allocations_attributes: [ { sale: recent, amount_cents: 5_000_00 } ])

    assert_equal 10_000_00, @customer.balance_cents
    assert_equal [ [ old, 10_000_00 ] ], @customer.open_invoices.map { [ _1.sale, _1.outstanding_cents ] }, "the disputed old sale stays open"
    assert_equal({ "current" => 0, "1_30" => 10_000_00, "31_60" => 0, "61_90" => 0, "over_90" => 0 }, @customer.ageing)
    assert_equal @customer.ageing, Customer.ageing_by_id([ @customer ])[@customer.id]

    @customer.customer_payments.create!(account: Current.account, amount_cents: 4_000_00, payment_method: "bank_transfer")
    assert_equal [ [ old, 6_000_00 ] ], @customer.open_invoices.map { [ _1.sale, _1.outstanding_cents ] }, "an unallocated payment goes to the oldest"
    assert_equal @customer.ageing, Customer.ageing_by_id([ @customer ])[@customer.id]
  end

  test "credit left on the account can be handed back, cash through the till" do
    account_sale(quantity: 40) # 10,000.00
    @customer.customer_payments.create!(account: Current.account, amount_cents: 12_000_00, payment_method: "bank_transfer")
    assert_equal(-2_000_00, @customer.balance_cents)

    too_much = @customer.customer_payments.create(account: Current.account, kind: "refund", amount_cents: 3_000_00, payment_method: "cash", shift: @shift)
    assert_match "more than the KES 2,000.00 credit", too_much.errors.full_messages.to_sentence
    no_till = @customer.customer_payments.create(account: Current.account, kind: "refund", amount_cents: 2_000_00, payment_method: "cash")
    assert_match "open shift", no_till.errors.full_messages.to_sentence

    refund = @customer.customer_payments.create!(account: Current.account, kind: "refund", amount_cents: 2_000_00, payment_method: "cash", shift: @shift)
    assert_equal(-2_000_00, refund.amount_cents, "a refund is kept as a negative credit, so sums stay right")
    assert_equal 0, @customer.balance_cents
    assert_equal 5_000_00 - 2_000_00, @shift.expected_cash_cents_now
    assert_equal "credit_refunded", @customer.events.last.action
    assert_equal [ [ 0, 2_000_00 ] ], @customer.reload.statement.entries.select { _1.description.start_with?("Credit") }.map { [ _1.credit_cents, _1.charge_cents ] }

    nothing_owed = @customer.customer_payments.create(account: Current.account, kind: "refund", amount_cents: 1_00, payment_method: "bank_transfer")
    assert_not nothing_owed.persisted?
  end

  test "bad debt is written off with a manager's approval and a reason, on the statement and in the activity" do
    old = account_sale(quantity: 40, days_ago: 45) # 10,000.00
    recent = account_sale(quantity: 20, days_ago: 5) # 5,000.00

    unapproved = @customer.customer_payments.create(account: Current.account, kind: "write_off", amount_cents: 10_000_00, reason: "Gone out of business")
    assert_match "approval PIN", unapproved.errors.full_messages.to_sentence
    no_reason = @customer.customer_payments.create(account: Current.account, kind: "write_off", amount_cents: 10_000_00, approver: users(:amina))
    assert_match "Reason", no_reason.errors.full_messages.to_sentence

    write_off = @customer.customer_payments.create!(account: Current.account, kind: "write_off", amount_cents: 10_000_00, approver: users(:amina),
      reason: "Gone out of business", allocations_attributes: [ { sale: old, amount_cents: 10_000_00 } ])
    assert_nil write_off.payment_method

    assert_equal 5_000_00, @customer.balance_cents
    assert_equal [ [ recent, 5_000_00 ] ], @customer.open_invoices.map { [ _1.sale, _1.outstanding_cents ] }
    event = @customer.events.last
    assert_equal "written_off", event.action
    assert_equal({ "amount" => 10_000_00, "approver" => "Amina Owner", "reason" => "Gone out of business" }, event.particulars.slice("amount", "approver", "reason"))
    assert_equal [ "Written off: Gone out of business" ], @customer.reload.statement(from: 60.days.ago.to_date).entries.map(&:description).grep(/Written/)
    assert_equal({}, @shift.report.account_payments_by_method, "a write-off isn't money through the till")
    @customer.customer_payments.create!(account: Current.account, amount_cents: 1_00, payment_method: "bank_transfer")
    report = Report::Payments.new(account: Current.account, period: Report::Period.for_preset("today"))
    assert_equal [ [ "Payments on account", "Bank transfer", 1_00 ] ], report.sections.last.rows, "nor is it money in the payments report"
  end

  test "a backdated statement ages what was owed at its end, not what's owed today" do
    account_sale(quantity: 40, days_ago: 45) # 10,000.00, due 15 days ago
    account_sale(quantity: 20, days_ago: 5) # 5,000.00
    @customer.customer_payments.create!(account: Current.account, amount_cents: 4_000_00, payment_method: "mobile_money", reference: "SJK4H7T2QP", paid_on: 3.days.ago.to_date)

    statement = @customer.statement(from: 40.days.ago.to_date, to: 10.days.ago.to_date)

    assert_equal 10_000_00, statement.closing_balance_cents
    assert_equal({ "current" => 0, "1_30" => 10_000_00, "31_60" => 0, "61_90" => 0, "over_90" => 0 }, statement.ageing)
    assert_equal statement.closing_balance_cents, statement.ageing.values.sum, "the buckets add up to the balance due"
    assert_equal 11_000_00, @customer.ageing.values.sum, "today's ageing still counts the payment"
  end

  test "who owes us lists only customers with a balance" do
    account_sale(quantity: 4)

    assert_equal [ [ @customer, 1_000_00 ] ], Current.account.customers.with_balances
  end

  test "cash taken on account goes into the shift's drawer" do
    refused = @customer.customer_payments.create(account: Current.account, amount_cents: 500_00, payment_method: "cash")
    assert_match "open shift", refused.errors.full_messages.to_sentence

    @customer.customer_payments.create!(account: Current.account, amount_cents: 500_00, payment_method: "cash", shift: @shift)
    assert_equal 5_000_00 + 500_00, @shift.expected_cash_cents_now
    assert_equal({ "cash" => 500_00 }, @shift.report.account_payments_by_method)
  end

  test "a delivery note goes from pending to dispatched to delivered with proof" do
    @customer.update!(address: "Plot 12, Mombasa Road")
    sale = account_sale(quantity: 4)
    note = Current.account.delivery_notes.create!(sale: sale)

    assert_equal "MAIN-DN00001", note.reference
    assert_equal "Plot 12, Mombasa Road", note.address
    assert_equal @customer.phone, note.contact_phone

    assert_not note.deliver(received_by: "Peter"), "not dispatched yet"
    assert_not note.dispatch(driver_name: "")
    assert note.dispatch(driver_name: "Joseph", vehicle: "KDA 123B")
    assert note.deliver(received_by: "Peter", proof_photo: { io: file_fixture("signed-note.png").open, filename: "signed-note.png", content_type: "image/png" })

    assert note.reload.delivered?
    assert note.proof_photo.attached?
    assert_equal %w[ created dispatched delivered ], note.events.order(:id).pluck(:action)
    assert DeliveryNotePdf.new(note).render.start_with?("%PDF")
  end

  test "only completed sales go out for delivery" do
    note = Current.account.delivery_notes.new(sale: @shift.current_sale, address: "Somewhere")

    assert_not note.valid?
    assert_includes note.errors[:sale], "must be a completed sale"
  end
end
