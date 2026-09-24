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

    # A sale during the count doesn't distort the variance.
    products(:acme_cement).move_stock(branch: branches(:acme_main), quantity: -5, reason: "sold")
    line.update!(counted_quantity: 48)

    assert_not count.approve, "must be submitted first"
    assert count.submit
    assert count.approve

    # Expected 50, counted 48: two bags missing, taken off the current 45.
    assert_equal 43, products(:acme_cement).stock_at(branches(:acme_main))
    assert_equal "count", StockMovement.where(source: count).sole.reason
    assert count.approved?
  end
end
