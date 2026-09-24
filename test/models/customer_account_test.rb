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

    @customer.customer_payments.create!(account: Current.account, amount_cents: 12_000_00, payment_method: "bank_transfer")

    assert_equal 3_000_00, @customer.balance_cents
    assert_equal [ [ recent, 3_000_00 ] ], @customer.open_invoices.map { [ _1.sale, _1.outstanding_cents ] }
    assert_equal 0, @customer.overdue_cents
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
