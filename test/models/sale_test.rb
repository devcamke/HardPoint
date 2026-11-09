require "test_helper"

class SaleTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @sale = @shift.current_sale
  end

  test "scanning adds lines, and scanning again adds to the same line" do
    @sale.add(products(:acme_cement))
    @sale.add(products(:acme_cement))
    @sale.add(products(:acme_nails), quantity: 1.5)

    assert_equal 2, @sale.lines.count
    assert_equal 2, @sale.lines.first.quantity
    assert_equal 160000 + 37500, @sale.total_cents
  end

  test "a line remembers which tax rate it was sold under, and its percentage even if that rate is later edited" do
    @sale.add(products(:acme_cement))
    line = @sale.lines.sole
    assert_equal tax_rates(:acme_vat), line.tax_rate_record
    assert_equal 16, line.tax_rate

    assert_not tax_rates(:acme_vat).destroy, "a rate that lines were sold under can't be deleted"
  end

  test "a sale whose discount is over the cashier's limit can't be completed without approval" do
    @sale.add(products(:acme_cement))
    @sale.update!(discount_cents: 40000) # half of 80,000, far past the 5% a cashier may give
    @sale.recalculate

    payment = @sale.pay(tender: "cash", tendered_cents: 40000)
    assert_match "needs a manager's approval PIN", payment.errors.full_messages.to_sentence
    assert @sale.reload.open?

    @sale.update!(discount_approver: users(:amina), approved_discount_percent: 50)
    payment = @sale.pay(tender: "cash", tendered_cents: 40000)
    assert payment.errors.empty?, payment.errors.full_messages.to_sentence
    assert @sale.reload.completed?
  end

  test "prices include tax; the tax share is worked out per line" do
    @sale.add(products(:acme_cement)) # 800.00 at 16% VAT
    @sale.add(products(:acme_screws), quantity: 10) # 50.00, no tax rate set → shop default 16%

    assert_equal 85000, @sale.total_cents
    assert_equal (80000 * 16 / 116.0).round + (5000 * 16 / 116.0).round, @sale.tax_cents
  end

  test "packs are priced as packs and take their pieces out of stock" do
    @sale.add(products(:acme_screws), product_unit: product_units(:acme_screws_box), quantity: 2)
    assert_equal 80000, @sale.total_cents

    @sale.pay(tender: "card", reference: "VISA 1234")
    assert_equal 800, products(:acme_screws).stock_at(branches(:acme_main))
  end

  test "a customer's price list and quantity breaks set the price" do
    @sale.add(products(:acme_cement), quantity: 2)
    assert_equal 160000, @sale.total_cents

    @sale.change_customer(customers(:acme_contractor))
    assert_equal 152000, @sale.reload.total_cents

    @sale.change_customer(nil)
    @sale.add(products(:acme_cement), quantity: 48)
    assert_equal 50 * 77000, @sale.reload.total_cents, "retail break from 50 bags"
  end

  test "line and cart discounts reduce the total and the tax" do
    @sale.add(products(:acme_cement), quantity: 2)
    @sale.lines.first.update!(discount_cents: 10000)
    @sale.update!(discount_cents: 5000)
    @sale.recalculate

    assert_equal 160000 - 10000 - 5000, @sale.total_cents
    assert_in_delta 145000 * 16 / 116.0, @sale.tax_cents, 1
  end

  test "discounts above the shop's limit need approval" do
    @sale.add(products(:acme_cement))
    @sale.lines.first.update!(discount_cents: 4000) # 5%
    assert_not @sale.discount_needs_approval?

    @sale.lines.first.update!(discount_cents: 8000) # 10%
    assert @sale.discount_needs_approval?
  end

  test "split payment completes the sale, numbers it and takes the stock" do
    @sale.add(products(:acme_cement), quantity: 3)
    @sale.add(products(:acme_pipe))

    card = @sale.pay(tender: "card", amount_cents: 200000, reference: "4411")
    assert card.persisted?
    assert @sale.reload.open?

    cash = @sale.pay(tender: "cash", tendered_cents: 200000)
    assert_equal 160000, cash.amount_cents
    assert_equal 40000, cash.change_cents

    assert @sale.reload.completed?
    assert_equal "MAIN-000001", @sale.receipt_number
    assert_equal users(:carl), @sale.cashier
    assert_equal 47, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal 2, products(:acme_pipe).stock_at(branches(:acme_main))
    assert_equal "sold", StockMovement.where(source: @sale).first.reason
  end

  test "receipt numbers run on per branch without gaps" do
    2.times do
      sale = @shift.current_sale
      sale.add(products(:acme_screws))
      sale.pay(tender: "cash", tendered_cents: 500)
    end

    assert_equal [ 1, 2 ], @shift.sales.completed.order(:number).pluck(:number)
  end

  test "non-cash can't be more than what's due, and mobile money needs its code" do
    @sale.add(products(:acme_screws))

    assert @sale.pay(tender: "card", amount_cents: 999999).errors[:amount].any?
    assert @sale.pay(tender: "mobile_money").errors[:reference].any?
    assert @sale.reload.open?
  end

  test "selling a kit takes its parts out of stock" do
    @sale.add(products(:acme_plumbing_kit))
    @sale.pay(tender: "cash", tendered_cents: 250000)

    assert_equal 1, products(:acme_pipe).stock_at(branches(:acme_main))
    assert_equal 980, products(:acme_screws).stock_at(branches(:acme_main))
  end

  test "on account needs a customer with enough credit" do
    @sale.add(products(:acme_cement))
    assert_match "Choose a customer", @sale.pay(tender: "on_account").errors.full_messages.to_sentence

    @sale.change_customer(customers(:acme_contractor))
    assert @sale.pay(tender: "on_account").persisted?
    assert_equal 76000, customers(:acme_contractor).balance_cents
  end

  test "serial numbers are required for serialised products" do
    products(:acme_pipe).update!(serialized: true)
    line = @sale.add(products(:acme_pipe))

    assert_match "serial number", @sale.pay(tender: "cash", tendered_cents: 120000).errors.full_messages.to_sentence
    line.update!(serial_number: "PVC-SN-001")
    assert @sale.pay(tender: "cash", tendered_cents: 120000).persisted?
    assert @sale.reload.completed?
  end

  test "voiding during the shift puts stock back and drops the takings" do
    @sale.add(products(:acme_cement), quantity: 2)
    @sale.pay(tender: "cash", tendered_cents: 160000)

    assert @sale.void(reason: "Rang up twice", approver: users(:amina))
    assert @sale.voided?
    assert_equal 50, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal 500000, @shift.expected_cash_cents_now
  end

  test "park and recall" do
    @sale.add(products(:acme_cement))
    assert @sale.park

    other = @shift.current_sale
    assert_not_equal @sale, other

    assert @sale.recall
    assert_equal @sale, @shift.current_sale
  end

  test "money is refunded only up to the money paid; what was put on account goes back to the account" do
    @sale.add(products(:acme_cement), quantity: 2) # 160,000: 600.00 in cash, the rest on account
    @sale.change_customer(customers(:acme_contractor))
    @sale.pay(tender: "cash", tendered_cents: 60000)
    @sale.pay(tender: "on_account", amount_cents: @sale.balance_due_cents, credit_approver: users(:amina))
    assert @sale.reload.completed?
    line = @sale.lines.first
    assert_equal 60000, SaleReturn.money_refundable_cents(@sale)

    one_bag_in_cash = accounts(:acme).sale_returns.new(sale: @sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line_id: line.id, quantity: 1 } ])
    assert_not one_bag_in_cash.valid?, "a bag is 760.00; only 600.00 was paid in money"
    assert_match "at most KES 600.00 in money", one_bag_in_cash.errors.full_messages.to_sentence

    on_account = accounts(:acme).sale_returns.create!(sale: @sale, shift: @shift, refund_method: "on_account", approver: users(:amina),
      lines_attributes: [ { sale_line_id: line.id, quantity: 1 } ])
    assert_equal 76000, on_account.total_cents
    assert_equal 60000, SaleReturn.money_refundable_cents(@sale), "crediting the account leaves the cash refundable"

    # A sale wholly on account can't be refunded in money at all.
    unpaid = @shift.current_sale
    unpaid.add(products(:acme_nails))
    unpaid.change_customer(customers(:acme_contractor))
    unpaid.pay(tender: "on_account", credit_approver: users(:amina))
    cash_back = accounts(:acme).sale_returns.new(sale: unpaid.reload, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line_id: unpaid.lines.first.id, quantity: 1 } ])
    assert_not cash_back.valid?
    assert_match "credit the customer's account instead", cash_back.errors.full_messages.to_sentence
  end

  test "goods returned at another branch go into that branch's stock, numbered there, from that till's drawer" do
    @sale.add(products(:acme_cement), quantity: 2)
    @sale.pay(tender: "cash", tendered_cents: 160000)
    yard = accounts(:acme).shifts.create!(branch: branches(:acme_yard), register: registers(:acme_yard), opened_by: users(:carl), opening_float_cents: 100000, opened_at: Time.current)
    main_before, yard_before = products(:acme_cement).stock_at(branches(:acme_main)), products(:acme_cement).stock_at(branches(:acme_yard))

    sale_return = accounts(:acme).sale_returns.create!(sale: @sale, shift: yard, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line_id: @sale.lines.first.id, quantity: 1, restock: true } ])

    assert_equal branches(:acme_yard), sale_return.branch
    assert_equal "YRD-R00001", sale_return.return_number
    assert_equal main_before, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal yard_before + 1, products(:acme_cement).stock_at(branches(:acme_yard))
    assert_equal 100000 - 80000, yard.expected_cash_cents_now
    assert_equal 500000 + 160000, @shift.expected_cash_cents_now, "the selling till's drawer keeps the sale and gives nothing back"
  end

  test "returns refund what was paid and restock by choice" do
    @sale.add(products(:acme_cement), quantity: 4)
    @sale.update!(discount_cents: 20000, discount_approver: users(:amina), approved_discount_percent: 6.25) # 320,000 → 300,000, a manager's discount
    @sale.recalculate
    @sale.pay(tender: "cash", tendered_cents: 300000)
    line = @sale.lines.first

    sale_return = accounts(:acme).sale_returns.create!(sale: @sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line_id: line.id, quantity: 2, restock: true } ])

    assert_equal 150000, sale_return.total_cents, "half of what was paid"
    assert_equal "MAIN-R00001", sale_return.return_number
    assert_equal 48, products(:acme_cement).stock_at(branches(:acme_main))

    too_many = accounts(:acme).sale_returns.new(sale: @sale, shift: @shift, refund_method: "cash",
      lines_attributes: [ { sale_line_id: line.id, quantity: 3 } ])
    assert_not too_many.valid?
    assert_match "Only 2", too_many.errors.full_messages.to_sentence
  end

  test "the drawer's expected cash follows sales, refunds and movements" do
    @sale.add(products(:acme_cement))
    @sale.pay(tender: "cash", tendered_cents: 100000)
    @shift.cash_movements.create!(account: accounts(:acme), kind: "drop", amount_cents: 300000, reason: "To safe")
    @shift.cash_movements.create!(account: accounts(:acme), kind: "payout", amount_cents: 20000, reason: "Transport")

    assert_equal 500000 + 80000 - 300000 - 20000, @shift.expected_cash_cents_now

    assert @shift.close(counted_cash_cents: 255000)
    assert_equal(-5000, @shift.variance_cents)
    assert_equal 1, @shift.report.sales_count
  end

  test "a shift with a sale in progress can't close" do
    @sale.add(products(:acme_cement))
    assert_not @shift.close(counted_cash_cents: 0)
    assert_match "Finish or discard", @shift.errors.full_messages.to_sentence
  end

  test "approval PINs belong to owners and managers" do
    memberships(:amina_acme).set_approval_pin("2468")
    assert_equal users(:amina), Approval.approver_for(accounts(:acme), "2468")
    assert_nil Approval.approver_for(accounts(:acme), "1234"), "a cashier's till PIN approves nothing"
    assert_not memberships(:carl_acme).set_approval_pin("1357")
  end
end
