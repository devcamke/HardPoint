require "test_helper"

# Stock promised to confirmed orders: held from other customers at the till when the shop chooses, and counted by the
# reorder list and branch rebalancing.
class StockReservationTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @main = branches(:acme_main)
    @cement = products(:acme_cement) # 50 bags at the main branch
    @order = order_for(30)
  end

  def order_for(bags, customer: customers(:acme_contractor))
    order = accounts(:acme).customer_orders.create!(branch: @main, customer: customer,
      lines_attributes: [ { account: accounts(:acme), product_code: "CEM-50", quantity: bags } ])
    assert order.confirm(approver: users(:amina))
    order
  end

  test "by default the till warns but sells what's promised, as before" do
    sale = @shift.current_sale
    line = sale.add(@cement, quantity: 25)
    assert line.persisted?, line.errors.full_messages.to_sentence
  end

  test "holding it, the till sells only what's free, and says which orders hold the rest" do
    accounts(:acme).update!(order_stock: "hold")
    sale = @shift.current_sale

    assert sale.add(@cement, quantity: 20).persisted?, "20 of the 50 are free"
    refused = sale.add(@cement, quantity: 1) # onto the same line, which is put back to 20
    assert_equal 20, sale.lines.sole.reload.quantity
    assert_equal "Only 20 Bamburi cement 50kg free at Main branch: 30 are held for order #{@order.reference}", refused.errors.full_messages.sole
    assert_equal [ 21, 20 ], [ accounts(:acme).stock_refusals.last.quantity.to_i, accounts(:acme).stock_refusals.last.on_hand.to_i ]
  end

  test "the order itself is collected from what it holds" do
    accounts(:acme).update!(order_stock: "hold")
    order_for(15, customer: customers(:acme_walk_in)) # 45 of the 50 now held

    sale = @shift.current_sale
    @order.load_into(sale)
    assert_empty @order.errors
    payment = sale.pay(tender: "cash", tendered_cents: sale.balance_due_cents)
    assert payment.persisted?, payment.errors.full_messages.to_sentence
  end

  test "cancelling an order frees what it held" do
    accounts(:acme).update!(order_stock: "hold")
    @order.cancel(reason: "Changed their mind")
    assert @shift.current_sale.add(@cement, quantity: 50).persisted?
  end

  test "the payment checks again, in case an order was confirmed while the sale was being rung up" do
    accounts(:acme).update!(order_stock: "hold")
    sale = @shift.current_sale
    sale.add(@cement, quantity: 20)
    order_for(5, customer: customers(:acme_walk_in))
    payment = sale.pay(tender: "cash", tendered_cents: 100_000_00)
    assert_not payment.persisted?
    assert_match "held for orders", payment.errors.full_messages.to_sentence
  end

  test "the reorder list counts what's promised as already gone, and shows it" do
    @cement.update!(reorder_level: 25)
    row = ReorderSuggestion.new(accounts(:acme), @main).rows.find { _1.product == @cement }
    assert_equal 30, row.held, "50 on the shelf is above 25, but 30 of them are promised"
    assert_operator row.needed, :>=, 25 * 2 - 20
  end

  test "rebalancing doesn't move away what's held for an order" do
    assert_equal 0, ReorderSuggestion.new(accounts(:acme), @main).spare(@cement.tap { _1.update!(reorder_level: 10) }),
      "20 free is exactly the 2 × 10 the branch wants for itself"
  end
end
