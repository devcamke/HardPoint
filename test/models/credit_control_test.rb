require "test_helper"

# Credit control: accounts held once an invoice is too long overdue, a manager lifting a hold for a while, and the
# Monday reminders to customers with overdue invoices.
class CreditControlTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @customer = customers(:acme_contractor) # 50,000.00 credit limit, 30 days' terms, +254722000111
    stock_up products(:acme_nails), 500
    accounts(:acme).update!(credit_hold_after_days: 15)
  end

  def account_sale(quantity: 4, days_ago: 0, approver: nil)
    sale = @shift.current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_nails), quantity: quantity) # 250.00 each
    payment = sale.pay(tender: "on_account", credit_approver: approver)
    sale.update_columns(completed_at: days_ago.days.ago) if payment.persisted?
    [ sale, payment ]
  end

  def customer = @customer.reload

  test "an account is held once an invoice is more than the shop's days overdue" do
    account_sale(days_ago: 40) # due 30 days after: 10 days overdue, not yet past 15
    assert_not customer.on_credit_hold?

    account_sale(days_ago: 50) # 20 days overdue
    hold = customer.credit_hold
    assert_equal [ 20, 1000_00, 15 ], [ hold.days_overdue, hold.overdue_cents, hold.after_days ]
    assert_match "Mwangi Builders Ltd's account is on hold: KES 1,000.00 is more than 15 days overdue (the oldest by 20 days)", hold.message(@customer.name)
  end

  test "a shop that doesn't hold accounts (0 days) never does" do
    accounts(:acme).update!(credit_hold_after_days: 0)
    account_sale(days_ago: 200)
    assert_not customer.on_credit_hold?
  end

  test "while held, nothing more goes on account without a manager's PIN, and paying the late invoice ends the hold" do
    late, = account_sale(days_ago: 60)

    _, refused = account_sale
    assert_not refused.persisted?
    assert_match "is on hold", refused.errors.full_messages.to_sentence
    @shift.current_sale.void(reason: "Held", by: users(:carl)) if @shift.current_sale.lines.any?

    sale, approved = account_sale(approver: users(:amina))
    assert approved.persisted?
    assert_equal users(:amina), sale.reload.credit_approver
    assert sale.events.find_by(action: "credit_approved").particulars["on_hold"]

    customer.customer_payments.create!(amount_cents: late.total_cents, payment_method: "bank_transfer", reference: "EFT 1")
    assert_not customer.on_credit_hold?, "the late invoice is paid"
  end

  test "a held customer's order can't be confirmed without a manager's PIN" do
    account_sale(days_ago: 60)
    order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customer,
      lines_attributes: [ { product: products(:acme_nails), quantity: 1, unit_price_cents: 250_00 } ])
    assert_not order.confirm
    assert_match "is on hold", order.errors.full_messages.to_sentence
    assert order.confirm(approver: users(:amina))
  end

  test "a manager lifts the hold for a while, with a reason, and can put it back" do
    account_sale(days_ago: 60)
    held = customer
    assert_not held.lift_credit_hold(by: users(:amina), days: 14, reason: "")
    assert held.lift_credit_hold(by: users(:amina), days: 14, reason: "Paying KES 20,000 on Friday")
    assert_not held.on_credit_hold?
    _, payment = account_sale
    assert payment.persisted?, "on account again while it's lifted"

    travel 15.days do
      assert customer.on_credit_hold?, "the lift has run out"
    end

    held.restore_credit_hold(by: users(:amina))
    assert customer.on_credit_hold?
  end

  test "each Monday, shops that ask remind customers with overdue invoices, by SMS" do
    account_sale(days_ago: 40) # overdue
    accounts(:acme).update!(weekly_reminders: "sms", sms_enabled: true)
    walk_in = customers(:acme_walk_in)
    assert_not_includes accounts(:acme).customers_to_remind, walk_in

    Current.reset
    assert_difference -> { Account.without_isolation { Sms::Message.where(purpose: "balance_reminder").count } }, 1 do
      WeeklyBalanceRemindersJob.perform_now
    end
    Current.account = accounts(:acme)
    assert_equal @customer, Sms::Message.find_by!(purpose: "balance_reminder").source
  end

  test "reminders skip customers who've asked not to be texted, and shops that don't send them" do
    account_sale(days_ago: 40)
    accounts(:acme).update!(sms_enabled: true)
    assert_equal 0, accounts(:acme).send_balance_reminders, "off by default"

    accounts(:acme).update!(weekly_reminders: "sms")
    @customer.update!(sms_opt_out: true)
    assert_empty accounts(:acme).customers_to_remind
  end

  test "on WhatsApp, the reminder carries the statement" do
    account_sale(days_ago: 40)
    accounts(:acme).update!(weekly_reminders: "whatsapp")
    assert_equal 1, accounts(:acme).send_balance_reminders
    assert_equal "hardpoint_balance_reminder", accounts(:acme).whatsapp_messages.sole.template
  end

  test "the preferences only take what they offer" do
    accounts(:acme).weekly_reminders = "carrier pigeon"
    assert_not accounts(:acme).valid?
    accounts(:acme).weekly_reminders = "whatsapp"
    accounts(:acme).credit_hold_after_days = 400
    assert_not accounts(:acme).valid?
  end
end
