require "test_helper"

class StockBatchTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @main, @yard = branches(:acme_main), branches(:acme_yard)
    @paint = products(:acme_cement)
    @paint.move_stock(branch: @main, quantity: -@paint.stock_at(@main), reason: "correction")
    @paint.update!(tracks_batches: true)
  end

  def receive(number, quantity, expires_on)
    @paint.move_stock(branch: @main, quantity: quantity, reason: "received", batch: { number: number, expires_on: expires_on })
  end

  def batch(number, branch: @main) = @paint.stock_batches.find_by!(branch: branch, number: number.upcase)

  test "stock out takes stock not in a batch first, then first-expiring-first, leaving expired batches" do
    receive "b-late", 10, 90.days.from_now.to_date
    receive "b-soon", 10, 10.days.from_now.to_date
    receive "b-gone", 5, 1.day.ago.to_date
    @paint.move_stock(branch: @main, quantity: 3, reason: "found")

    movement = @paint.move_stock(branch: @main, quantity: -15, reason: "damaged")

    assert_equal [ 0, 0, 8, 5 ], [ @paint.unbatched_stock_at(@main), batch("b-soon").quantity, batch("b-late").quantity, batch("b-gone").quantity ]
    assert_equal 13, @paint.stock_at(@main)
    assert_equal [ -3, -10, -2 ], @paint.stock_movements.where(reason: "damaged").order(:id).pluck(:quantity), "one ledger line per batch"
    assert_equal 13, movement.balance

    @paint.move_stock(branch: @main, quantity: -12, reason: "damaged")
    assert_equal 1, batch("b-gone").quantity, "expired stock goes only when nothing else is left"
  end

  test "a sale's batches: shown for a recall, and put back by returns" do
    receive "A1", 4, 20.days.from_now.to_date
    receive "A2", 10, 60.days.from_now.to_date
    sale = shifts(:acme_front_open).current_sale
    sale.change_customer(customers(:acme_contractor))
    sale.add(@paint, quantity: 6)
    sale.pay(tender: "card", reference: "VISA 1")
    assert_equal [ 0, 8 ], [ batch("A1").quantity, batch("A2").quantity ]
    assert_equal [ sale ], batch("A1").sales.to_a
    assert_equal [ sale ], batch("A2").sales.to_a

    sale.reload
    accounts(:acme).sale_returns.create!(sale: sale, shift: shifts(:acme_front_open), refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.sole, quantity: 3, restock: true } ])
    assert_equal 11, batch("A1").quantity + batch("A2").quantity
    assert_equal 0, @paint.unbatched_stock_at(@main)

    sale.lines.sole.restore_stock(3, source: sale) # as a void of what's left would
    assert_equal [ 4, 10 ], [ batch("A1").quantity, batch("A2").quantity ], "everything went back where it came from"
  end

  test "transfers take batches with them, and a cancelled transfer brings them back" do
    receive "T1", 6, 30.days.from_now.to_date
    transfer = accounts(:acme).stock_transfers.create!(from_branch: @main, to_branch: @yard, lines_attributes: [ { product_code: "CEM-50", quantity: 4 } ])
    assert_equal 2, batch("T1").quantity
    transfer.receive
    arrived = batch("T1", branch: @yard)
    assert_equal [ 4, 30.days.from_now.to_date ], [ arrived.quantity, arrived.expires_on ]

    other = accounts(:acme).stock_transfers.create!(from_branch: @main, to_branch: @yard, lines_attributes: [ { product_code: "CEM-50", quantity: 2 } ])
    other.cancel
    assert_equal 2, batch("T1").quantity
  end

  test "deliveries need a batch number, and write-offs come out of the batch chosen" do
    order = accounts(:acme).purchase_orders.create!(supplier: suppliers(:acme_cement_distributor), branch: @main, lines_attributes: [ { product_code: "CEM-50", quantity: 10 } ])
    order.mark_sent
    receipt = accounts(:acme).goods_receipts.new(supplier: order.supplier, branch: @main, purchase_order: order,
      lines_attributes: [ { purchase_order_line_id: order.lines.sole.id, quantity: 10 } ])
    assert_not receipt.valid?
    assert_match "needs its batch number", receipt.errors.full_messages.to_sentence

    receipt.lines.first.assign_attributes(batch_number: " bb-2026-11 ", expires_on: 5.days.ago.to_date)
    receipt.save!
    delivered = batch("BB-2026-11")
    assert_equal 10, delivered.quantity
    assert delivered.expired?
    assert_includes accounts(:acme).stock_batches.expired, delivered

    assert_raises(ArgumentError) { delivered.write_off(11, reason: "expired") }
    delivered.write_off(10, reason: "expired", note: "Returned to Bamburi")
    assert_equal [ 0, 0 ], [ delivered.reload.quantity, @paint.stock_at(@main) ]
    assert_equal "expired", delivered.stock_movements.last.reason
  end
end
