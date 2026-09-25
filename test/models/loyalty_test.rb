require "test_helper"

class LoyaltyTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @program = accounts(:acme).create_loyalty_program!(enabled: true, points_per_100: 2, point_value_cents: 50, min_redeem_points: 20)
    @shift = shifts(:acme_front_open)
    @customer = customers(:acme_walk_in)
  end

  def sell(quantity: 1, customer: @customer, &payments)
    sale = @shift.current_sale
    sale.change_customer(customer)
    sale.add(products(:acme_cement), quantity: quantity) # 800.00 each
    payments ? payments.call(sale) : sale.pay(tender: "card", reference: "VISA 1")
    sale.reload
  end

  test "named customers earn on what they pay; walk-ins and a switched-off scheme earn nothing" do
    sale = sell(quantity: 2)
    assert_equal 32, sale.points_earned, "KES 1,600 at 2 points per 100"
    assert_equal 32, @customer.points_balance

    assert_equal 0, sell(customer: nil).loyalty_entries.count
    @program.update!(enabled: false)
    assert_equal 0, sell.points_earned
    assert_equal "1.0", @program.reward_percent.to_s
  end

  test "points pay at the till, whole points, capped by the balance; no points on the part paid with them" do
    sell(quantity: 2) # 32 points, worth 16.00
    refused = @shift.current_sale.tap { _1.change_customer(customers(:acme_contractor)); _1.add(products(:acme_nails)) }.pay(tender: "points")
    assert_match "at least 20", refused.errors.full_messages.to_sentence
    @shift.current_sale.discard

    sale = sell do |sale|
      payment = sale.pay(tender: "points")
      assert_equal [ 32, 16_00 ], [ payment.points, payment.amount_cents ]
      assert_equal 0, @customer.points_balance
      assert_raises(ArgumentError) { sale.change_customer(customers(:acme_contractor)) }
      sale.pay(tender: "cash", tendered_cents: 800_00)
    end
    assert_equal ((800_00 - 16_00) / 100 * 2 / 100), sale.points_earned
  end

  test "removing a points payment gives the points back; a void reverses everything" do
    sell(quantity: 3) # 48 points
    sale = @shift.current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_cement))
    payment = sale.pay(tender: "points", amount_cents: 10_00)
    assert_equal 28, @customer.points_balance
    sale.remove_payment(payment)
    assert_equal 48, @customer.points_balance

    sale.pay(tender: "points", amount_cents: 10_00)
    sale.pay(tender: "card", reference: "VISA 2")
    assert_equal 28 + 15, @customer.points_balance
    sale.reload.void(reason: "Wrong customer", by: users(:amina))
    assert_equal 48, @customer.points_balance
  end

  test "returns take back their share of the points earned" do
    sale = sell(quantity: 4) # 64 points
    accounts(:acme).sale_returns.create!(sale: sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.sole, quantity: 1, restock: true } ])
    assert_equal 64 - 16, @customer.points_balance
    assert_equal 48 * 50, @program.liability_cents
  end

  test "adjustments need a reason" do
    assert_not @customer.loyalty_entries.new(account: accounts(:acme), kind: "adjusted", points: 10).valid?
    assert @customer.loyalty_entries.create!(account: accounts(:acme), kind: "adjusted", points: 10, note: "Goodwill")
  end
end
