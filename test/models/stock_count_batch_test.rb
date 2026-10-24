require "test_helper"

class StockCountBatchTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @main = branches(:acme_main)
    @cement = products(:acme_cement)
    @cement.move_stock(branch: @main, quantity: -@cement.stock_at(@main), reason: "correction")
    @cement.update!(tracks_batches: true)
    @cement.move_stock(branch: @main, quantity: 10, reason: "received", batch: { number: "A1", expires_on: 20.days.from_now.to_date })
    @cement.move_stock(branch: @main, quantity: 6, reason: "received", batch: { number: "A2", expires_on: 60.days.from_now.to_date })
    @cement.move_stock(branch: @main, quantity: 3, reason: "found")
  end

  def start = accounts(:acme).stock_counts.create!(branch: @main, category: categories(:acme_building))
  def batch(number) = @cement.stock_batches.find_by!(branch: @main, number: number)

  test "batch-tracked products are counted batch by batch, and approving corrects each batch" do
    count = start
    line = count.lines.find_by!(product: @cement)
    assert_equal [ [ "A1", 10 ], [ "A2", 6 ], [ nil, 3 ] ], line.batch_counts.in_order.map { [ _1.number, _1.expected_quantity.to_i ] }
    assert line.by_batch?
    assert_not count.lines.find_by(product: products(:acme_nails)), "only the category counted"

    line.count_batch(number: "a1", quantity: 8)
    line.count_batch(number: "", quantity: 3)
    found = line.count_batch(number: "B9", quantity: 2, mode: "add", expires_on: 90.days.from_now.to_date)
    line.count_batch(number: "B9", quantity: 2, mode: "add")
    assert found.found?
    assert_equal 19 - 2 + 4, line.reload.counted_quantity, "A2 not counted: left as it is"

    count.submit
    count.approve(users(:amina))
    assert_equal [ 8, 6, 4 ], [ batch("A1").quantity, batch("A2").quantity, batch("B9").quantity ]
    assert_equal 90.days.from_now.to_date, batch("B9").expires_on
    assert_equal 3, @cement.unbatched_stock_at(@main)
    assert_equal 21, @cement.stock_at(@main)
    assert_equal [ -2, 4 ], @cement.stock_movements.where(reason: "count").order(:id).pluck(:quantity)
  end

  test "a batch sold from during the count doesn't go below nothing" do
    count = start
    line = count.lines.find_by!(product: @cement)
    @cement.move_stock(branch: @main, quantity: -9, reason: "sold") # 3 not in a batch, then 6 of A1
    line.count_batch(number: "A1", quantity: 1)

    count.submit
    count.approve(users(:amina))
    assert_equal 0, batch("A1").quantity
    assert StockBatch.where(product: @cement).all? { _1.quantity >= 0 }
    assert_equal 19 - 9 - 9, @cement.stock_at(@main), "the 9 short still comes off"
  end

  test "counting a batch-tracked product's total directly is refused; the line counts its batches" do
    line = start.lines.find_by!(product: @cement)
    row = line.count_batch(number: "A1", quantity: 1.5)
    assert_match "whole number", row.errors.full_messages.to_sentence
    assert_nil line.reload.counted_quantity
  end
end
