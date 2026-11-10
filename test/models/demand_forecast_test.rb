require "test_helper"

class DemandForecastTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @main = branches(:acme_main)
    @cement = products(:acme_cement) # 50 at the main branch, supplied in 3 days
  end

  def sell(quantity, days_ago:, product: @cement)
    movement = product.move_stock(branch: @main, quantity: -quantity, reason: "sold")
    StockMovement.where(id: movement.id).update_all(created_at: days_ago.days.ago)
  end

  def forecast(product = @cement) = DemandForecast.new(accounts(:acme), @main).for(product, supplier_product: product.preferred_supplier_product)

  test "steady sales: demand is the daily average, with no margin needed for busy days" do
    30.times { sell(1, days_ago: _1) }
    expected = forecast
    assert_equal 1, expected.daily
    assert_equal 0, expected.safety.round(6)
    assert_equal 3, expected.suggested_level, "a bag a day for a three-day delivery"
    assert_empty expected.notes
  end

  test "what the till turned away counts as demand, once a day however often the cashier tried" do
    3.times { accounts(:acme).stock_refusals.create!(branch: @main, product: @cement, quantity: 60, on_hand: 50) }
    expected = forecast
    assert_equal 10, expected.unmet, "the shelf was 10 short of the biggest request"
    assert_includes expected.notes, "10 more asked for at the till"
  end

  test "lumpy sales get a margin for busy days" do
    sell(30, days_ago: 2)
    expected = forecast
    assert_operator expected.safety, :>, 10
    assert_operator expected.suggested_level, :>, expected.daily * 3
  end

  test "a supplier's real delivery time, once it has delivered twice, beats what was typed in" do
    supplier = suppliers(:acme_cement_distributor)
    2.times do |index|
      order = accounts(:acme).purchase_orders.create!(supplier: supplier, branch: @main, lines_attributes: [ { product_code: "CEM-50", quantity: 10, unit_cost: "700" } ])
      order.mark_sent
      order.update_columns(sent_at: (20 + index * 10).days.ago)
      receipt = accounts(:acme).goods_receipts.create!(supplier: supplier, branch: @main, purchase_order: order,
        lines_attributes: [ { purchase_order_line_id: order.lines.sole.id, quantity: 10 } ])
      receipt.update_columns(created_at: (11 + index * 10).days.ago)
    end
    expected = forecast
    assert_equal [ 9, true ], [ expected.lead_time, expected.lead_time_measured ]
    assert_includes expected.notes, "deliveries take 9 days"
  end

  test "this time last year lifts demand for a busy season ahead" do
    # A year of a bag a day, then twice that in the weeks ahead last year.
    (17...365).step(1) { |days_ago| sell(1, days_ago: days_ago) unless days_ago.between?(348, 364) }
    (348..364).each { |days_ago| sell(2, days_ago: days_ago) }
    expected = forecast
    assert_operator expected.season, :>, 1.5
    assert_match(/busier season/, expected.notes.join)
  end

  test "a level is suggested higher whenever demand says so, and lower only with ten days of sales to go on" do
    @cement.update!(reorder_level: 40)
    sell(5, days_ago: 1) # one day's sales: not enough to cut 40 down
    row = -> { ReorderSuggestion.new(accounts(:acme), @main).rows.find { _1.product == @cement } }
    @cement.move_stock(branch: @main, quantity: -20, reason: "damaged") # down to 25, below the level, so it's listed
    assert_nil row.().suggested_level

    12.times { sell(1, days_ago: _1 + 2) }
    assert_operator row.().suggested_level, :<, 40, "now there's enough to go on"
  end
end
