require "test_helper"

class StockTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
  end

  test "moving stock updates the level and appends to the ledger" do
    cement = products(:acme_cement)

    movement = cement.move_stock(branch: branches(:acme_main), quantity: -3, reason: "damaged")

    assert_equal 47, cement.stock_at(branches(:acme_main))
    assert_equal 47, movement.balance
    assert_equal users(:amina), movement.creator
    assert movement.readonly?
  end

  test "levels always equal the sum of their movements" do
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: 12, reason: "received")
    products(:acme_nails).move_stock(branch: branches(:acme_yard), quantity: 4.25, reason: "found")

    ledger = StockMovement.group(:branch_id, :product_id).sum(:quantity)
    levels = StockLevel.all.to_h { [ [ _1.branch_id, _1.product_id ], _1.quantity ] }
    assert_equal ledger, levels
  end

  test "adjustments need a matching direction, whole units, and can't go below zero" do
    adjust = ->(**attributes) { accounts(:acme).stock_adjustments.new(branch: branches(:acme_main), **attributes) }

    assert_not adjust.(product: products(:acme_cement), quantity: 5, reason: "damaged").valid?
    assert_not adjust.(product: products(:acme_cement), quantity: 1.5, reason: "found").valid?
    assert_not adjust.(product: products(:acme_cement), quantity: -51, reason: "damaged").valid?
    assert adjust.(product: products(:acme_nails), quantity: 1.5, reason: "found").valid?, "kilograms can be fractional"

    assert_difference -> { products(:acme_cement).stock_at(branches(:acme_main)) }, -2 do
      adjust.(product: products(:acme_cement), quantity: -2, reason: "damaged", note: "Split bags").save!
    end
  end

  test "transfers leave the source when sent and arrive when received" do
    transfer = accounts(:acme).stock_transfers.create!(from_branch: branches(:acme_main), to_branch: branches(:acme_yard),
      lines_attributes: [ { product_code: "CEM-50", quantity: 20 }, { product_code: "6001234500012", quantity: 100 } ])

    assert transfer.in_transit?
    assert_equal 30, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal 10, products(:acme_cement).stock_at(branches(:acme_yard))

    assert transfer.receive
    assert transfer.received?
    assert_equal 30, products(:acme_cement).stock_at(branches(:acme_yard))
    assert_equal 100, products(:acme_screws).stock_at(branches(:acme_yard))
    assert_not transfer.receive, "can only be received once"
  end

  test "cancelling a transfer returns the stock" do
    transfer = accounts(:acme).stock_transfers.create!(from_branch: branches(:acme_main), to_branch: branches(:acme_yard),
      lines_attributes: [ { product_code: "CEM-50", quantity: 20 } ])

    transfer.cancel

    assert transfer.cancelled?
    assert_equal 50, products(:acme_cement).stock_at(branches(:acme_main))
  end

  test "transfers can't send more than is on hand, unknown codes, or the same branch" do
    too_much = accounts(:acme).stock_transfers.new(from_branch: branches(:acme_yard), to_branch: branches(:acme_main),
      lines_attributes: [ { product_code: "CEM-50", quantity: 11 } ])
    assert_not too_much.valid?
    assert_match "Only 10", too_much.errors.full_messages.to_sentence

    unknown = accounts(:acme).stock_transfers.new(from_branch: branches(:acme_main), to_branch: branches(:acme_yard),
      lines_attributes: [ { product_code: "HAM-16", quantity: 1 } ])
    assert_not unknown.valid?, "another shop's SKU isn't found"

    same = accounts(:acme).stock_transfers.new(from_branch: branches(:acme_main), to_branch: branches(:acme_main),
      lines_attributes: [ { product_code: "CEM-50", quantity: 1 } ])
    assert_not same.valid?
  end

  test "a stock take snapshots, records counts, and posts variances on approval" do
    count = accounts(:acme).stock_counts.create!(branch: branches(:acme_main), category: categories(:acme_building))
    line = count.lines.find_by!(product: products(:acme_cement))
    assert_equal 50, line.expected_quantity
    assert_equal 1, count.lines.count, "only the category's stocked products"

    # Five sold before the counter reaches the shelf: the shelf shows 45 and so does the system.
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -5, reason: "sold")
    assert line.record(48)
    assert_equal 45, line.expected_quantity, "measured against the level at the moment of counting"
    assert_equal 3, line.variance, "three more on the shelf than the system knew"

    # One sold after the shelf was counted: the difference is posted as a delta, so it isn't put back.
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -1, reason: "sold")

    assert_not count.approve, "must be submitted first"
    assert count.submit
    assert count.approve

    assert_equal 44 + 3, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal [ "count", 3 ], StockMovement.where(source: count).sole.values_at(:reason, :quantity)
    assert count.approved?
  end

  test "a count that agrees with the shelf posts nothing, however many sales happened during the take" do
    count = accounts(:acme).stock_counts.create!(branch: branches(:acme_main), category: categories(:acme_building))
    line = count.lines.find_by!(product: products(:acme_cement))
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -2, reason: "sold")

    line.record(48)
    count.submit
    count.approve

    assert_equal 0, line.reload.variance
    assert_equal 48, products(:acme_cement).stock_at(branches(:acme_main))
    assert_not StockMovement.where(source: count).exists?
  end

  test "counting in several places adds up, against the live level" do
    count = accounts(:acme).stock_counts.create!(branch: branches(:acme_main), category: categories(:acme_building))
    line = count.lines.find_by!(product: products(:acme_cement))

    line.record(30, mode: "add")
    line.record(18, mode: "add")
    assert_equal 48, line.counted_quantity
    line.record(47)
    assert_equal 47, line.counted_quantity, "set corrects the total"
    assert line.record(nil), "and a count can be cleared"
    assert_nil line.counted_quantity
  end
end
