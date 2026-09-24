require "test_helper"

class CustomerOrderTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
  end

  def quote(customer: customers(:acme_contractor), lines: { "CEM-50" => 10, "PVC-2" => 2 }, **attributes)
    Current.account.customer_orders.create!(branch: branches(:acme_main), customer: customer,
      lines_attributes: lines.map { |code, quantity| { account: Current.account, product_code: code, quantity: quantity } }, **attributes)
  end

  test "a quote is numbered per branch, valid for two weeks, and priced for the customer" do
    order = quote

    assert order.quote?
    assert_equal "MAIN-O00001", order.reference
    assert_equal Date.current + 14.days, order.valid_until
    assert_equal 76000, order.lines.first.unit_price_cents, "contractor price for cement"
    assert_equal 10 * 76000 + 2 * 120000, order.total_cents
    assert_equal order.lines.sum(&:tax_cents), order.tax_cents
  end

  test "an expired quote can't be confirmed until it's re-dated" do
    order = quote
    order.update_columns(valid_until: Date.yesterday)

    assert_not order.confirm
    assert_match "expired", order.errors.full_messages.to_sentence

    order.update!(valid_until: Date.tomorrow)
    assert order.confirm
    assert order.reload.ordered?
    assert order.ordered_at
  end

  test "taking a deposit confirms the quote; cash needs an open shift" do
    order = quote

    refused = order.take_deposit(amount_cents: 100_00, tender: "cash")
    assert_match "open shift", refused.errors.full_messages.to_sentence
    assert order.reload.quote?

    order.take_deposit(amount_cents: 2000_00, tender: "cash", shift: @shift)
    assert order.reload.ordered?
    assert_equal 2000_00, order.deposit_balance_cents
    assert_equal 5000_00 + 2000_00, @shift.expected_cash_cents_now
  end

  test "refunds can't exceed the deposit held, and an order can't be cancelled while holding one" do
    order = quote
    order.take_deposit(amount_cents: 1000_00, tender: "mobile_money", reference: "QWE123RTY")

    assert_not order.cancel
    assert_match "Refund", order.errors.full_messages.to_sentence

    assert_match "more than", order.refund_deposit(amount_cents: 1500_00, tender: "cash", shift: @shift).errors.full_messages.to_sentence
    order.refund_deposit(amount_cents: 1000_00, tender: "cash", shift: @shift)
    assert_equal 0, order.deposit_balance_cents
    assert_equal 5000_00 - 1000_00, @shift.expected_cash_cents_now

    assert order.cancel
    assert order.reload.cancelled?
  end

  test "collecting at the till keeps the quoted prices, uses the deposit and marks the order collected" do
    order = quote
    order.take_deposit(amount_cents: 3000_00, tender: "card", reference: "VISA 4242")
    products(:acme_cement).update!(price_cents: 90000)

    sale = @shift.current_sale
    assert order.load_into(sale)
    assert_equal order.total_cents, sale.reload.total_cents
    assert_equal customers(:acme_contractor), sale.customer

    # Anything else is priced as usual.
    sale.add(products(:acme_nails))
    assert_equal order.total_cents + 25000, sale.reload.total_cents
    assert_equal 3000_00, sale.deposit_available_cents

    deposit = sale.pay(tender: "deposit")
    assert_equal 3000_00, deposit.amount_cents
    sale.pay(tender: "cash", tendered_cents: sale.balance_due_cents)

    assert sale.reload.completed?
    assert order.reload.collected?
    assert_equal 0, order.deposit_balance_cents
    assert_equal 50 - 10, products(:acme_cement).stock_at(branches(:acme_main))
  end

  test "an order only loads into an empty cart" do
    order = quote
    sale = @shift.current_sale
    sale.add(products(:acme_nails))

    assert_not order.load_into(sale)
    assert_match "Finish or park", order.errors.full_messages.to_sentence
  end

  test "voiding the collection puts the order back to ready" do
    order = quote(lines: { "NAIL-3" => 2 })
    sale = @shift.current_sale
    order.load_into(sale)
    sale.pay(tender: "card", reference: "VISA 1")
    assert order.reload.collected?

    sale.void(reason: "Wrong customer", by: users(:amina))
    assert order.reload.ready?
  end

  test "lines can't change once an order is ready" do
    order = quote
    order.confirm
    order.mark_ready

    assert_not order.update(lines_attributes: [ { id: order.lines.first.id, quantity: 20 } ])
    assert_match "can't be changed", order.errors.full_messages.to_sentence
  end
end
