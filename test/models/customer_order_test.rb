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

  test "confirming a quote worth more than the customer's credit left needs a manager's approval, as the till does" do
    order = quote(lines: { "CEM-50" => 70 }) # 53,200.00 at contractor prices, against a 50,000.00 limit

    assert_not order.confirm
    assert_match "Mwangi Builders Ltd has only KES 50,000.00 of credit left", order.errors.full_messages.to_sentence
    assert order.reload.quote?

    assert order.confirm(approver: users(:amina))
    assert order.ordered?
    assert_equal %w[ credit_approved confirmed ], order.events.order(:id).last(2).pluck(:action)
    assert_equal "Amina Owner", order.events.find_by(action: "credit_approved").particulars["approver"]

    assert quote(lines: { "CEM-50" => 10 }).confirm, "within the credit left, nothing to approve"
    assert quote(customer: customers(:acme_walk_in), lines: { "CEM-50" => 70 }).confirm, "a cash customer pays at the till"

    with_deposit = quote(lines: { "CEM-50" => 70 })
    with_deposit.take_deposit(amount_cents: 1_000_00, tender: "mobile_money", reference: "SJK4H7T2QR")
    assert with_deposit.reload.ordered?, "money down confirms it; the till checks the credit again when the rest goes on account"
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

  test "a quote priced under a promotion is collected under it, so the promotion's results count it" do
    promotion = Current.account.promotions.create!(name: "Cement week", kind: "percent_off", percent_off: 10, product_ids: [ products(:acme_cement).id ],
      starts_on: Date.current, ends_on: Date.current + 7)
    order = quote(customer: customers(:acme_walk_in), lines: { "CEM-50" => 2 })
    assert_equal promotion, order.lines.sole.promotion

    sale = @shift.current_sale
    order.load_into(sale)
    assert_equal promotion, sale.lines.sole.promotion
    sale.pay(tender: "cash", tendered_cents: sale.balance_due_cents)

    result = Promotion::Results.for([ promotion ]).fetch(promotion.id)
    assert_equal [ 1, 2, 2 * 720_00 ], [ result.sales, result.units, result.takings_cents ]
  end

  test "collecting part of an order leaves the rest waiting, and the next collection takes only that" do
    order = quote(lines: { "CEM-50" => 10, "PVC-2" => 2 })
    order.confirm
    sale = @shift.current_sale
    order.load_into(sale)
    cement = sale.lines.find { _1.product == products(:acme_cement) }
    cement.update!(quantity: 4)
    sale.recalculate
    sale.pay(tender: "cash", tendered_cents: sale.balance_due_cents)

    assert order.reload.ready?, "not collected: six bags are still to come"
    assert_equal [ 4, 2 ], order.lines.map(&:collected_quantity)
    assert_equal [ 6, 0 ], order.lines.map(&:remaining_quantity)
    assert_equal "part_collected", order.events.chronologically.first.action

    second = @shift.current_sale
    assert order.load_into(second)
    assert_equal [ [ products(:acme_cement), 6 ] ], second.lines.map { [ _1.product, _1.quantity ] }
    second.pay(tender: "cash", tendered_cents: second.balance_due_cents)
    assert order.reload.collected?
    assert_not order.collectable?

    # Voiding the second sale puts just those six back on the order.
    second.void(reason: "Wrong customer", by: users(:amina))
    assert order.reload.ready?
    assert_equal [ 6, 0 ], order.lines.map(&:remaining_quantity)
  end

  test "confirmed orders reserve stock; quotes don't, and the order being collected isn't counted against itself" do
    main = branches(:acme_main)
    assert_equal 50, products(:acme_cement).available_at(main)

    order = quote(lines: { "CEM-50" => 30 })
    assert_equal 50, products(:acme_cement).available_at(main), "a quote promises nothing"
    order.confirm
    assert_equal 30, products(:acme_cement).reserved_at(main)
    assert_equal 20, products(:acme_cement).available_at(main)
    assert_equal 50, products(:acme_cement).available_at(main, except: order)

    sale = @shift.current_sale
    order.load_into(sale)
    sale.pay(tender: "cash", tendered_cents: sale.balance_due_cents)
    assert_equal 0, products(:acme_cement).reserved_at(main)
    assert_equal 20, products(:acme_cement).available_at(main)
  end

  test "a kept deposit is sold as a forfeited deposit, paid from the deposit, and the order is cancelled" do
    order = quote(lines: { "CEM-50" => 10 })
    order.take_deposit(amount_cents: 3000_00, tender: "card", reference: "VISA 4242")

    assert_not order.forfeit_deposit(shift: @shift, approver: nil)
    assert_match "approval PIN", order.errors.full_messages.to_sentence

    assert order.forfeit_deposit(shift: @shift, approver: users(:amina), reason: "Never came back"), order.errors.full_messages.to_sentence
    assert order.reload.cancelled?
    assert_equal 0, order.deposit_balance_cents

    sale = order.sales.sole
    assert sale.completed?
    assert_equal [ "Forfeited deposit", 3000_00, "deposit" ], [ sale.lines.sole.product.name, sale.total_cents, sale.payments.sole.tender ]
    assert_equal 50, products(:acme_cement).stock_at(branches(:acme_main)), "no goods left the shelf"
    assert_equal "Never came back", order.events.find_by(action: "cancelled").particulars["reason"]
    assert_not accounts(:acme).forfeited_deposit_product.active?, "not something the till offers"
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
