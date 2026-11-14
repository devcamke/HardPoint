require "test_helper"

class Product::CuttingTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @main, @yard = branches(:acme_main), branches(:acme_yard)
    metre = accounts(:acme).units.create!(name: "Metre", abbreviation: "m", fractional: true)
    @bar = accounts(:acme).products.create!(name: "Y12 steel bar", sku: "Y12", unit: metre, price_cents: 20000, cost_cents: 15000, stock_length: 6, scrap_below: 0.5)
    @bar.move_stock(branch: @main, quantity: 30, reason: "received")
    @sale = shifts(:acme_front_open).current_sale
  end

  def offcuts(branch = @main) = @bar.offcuts.where(branch: branch).order(:length).pluck(:length).map(&:to_f)
  def rack(branch = @main) = @bar.lengths_at(branch).then { [ _1.full, _1.part.to_f, _1.offcuts.map(&:to_f) ] }
  def sell(*pieces) = @bar.move_stock(branch: @main, quantity: -pieces.sum.to_d, reason: "sold", pieces: pieces.map(&:to_d), allow_negative: false)
  def notes(reason = "sold") = @bar.stock_movements.where(reason: reason).order(:id).pluck(:note)

  test "a cut comes from a full length and leaves an offcut; the next cut that fits comes from the offcut" do
    assert_equal [ 5, 0.0, [] ], rack

    sell 2.5
    assert_equal [ 4, 0.0, [ 3.5 ] ], rack
    assert_equal 27.5, @bar.stock_at(@main)

    sell 3
    assert_equal [ 4, 0.0, [ 0.5 ] ], rack, "the 3.5 m offcut, not another full length"
    assert_equal [ "2.5 m cut from a 6 m length, leaving a 3.5 m offcut", "3 m cut from a 3.5 m offcut, leaving a 0.5 m offcut" ], notes
  end

  test "the shortest piece that's long enough is used, so short offcuts go first" do
    sell 2    # leaves 4
    sell 4.5  # from a full length, leaves 1.5
    assert_equal [ 1.5, 4.0 ], offcuts

    sell 1.2
    assert_equal [ 0.3, 4.0 ].last, offcuts.last, "the 4 m offcut is untouched"
    assert_equal [ 4.0 ], offcuts, "1.5 − 1.2 leaves 0.3, under the 0.5 m worth keeping"
    assert_equal [ "Left over from cutting, too short to keep" ], notes("cutting_waste")
    assert_equal(-0.3, @bar.stock_movements.find_by!(reason: "cutting_waste").quantity.to_f)
    assert_equal 30 - 2 - 4.5 - 1.2 - 0.3, @bar.stock_at(@main).to_f, "the scrap has left the stock too"
  end

  test "several pieces of one sale share a length; whole lengths are taken whole" do
    sell 2.5, 2.5, 6, 6
    assert_equal [ 2, 0.0, [ 1.0 ] ], rack
    assert_equal [ "2 full lengths of 6 m", "2.5 m cut from a 6 m length, leaving a 3.5 m offcut", "2.5 m cut from a 3.5 m offcut, leaving a 1 m offcut" ], notes
    assert_equal 13, @bar.stock_at(@main)
  end

  test "a quantity that doesn't say how it's cut is full lengths and one last piece" do
    assert_equal [ 6, 6, 2.5 ], @bar.pieces_for(14.5).map(&:to_f)
    assert_equal [ 2.5, 2.5, 2.5 ], @bar.pieces_for(7.5, 2.5).map(&:to_f)

    @bar.move_stock(branch: @main, quantity: -14.5, reason: "sold")
    assert_equal [ 2, 0.0, [ 3.5 ] ], rack
  end

  test "stock that isn't whole lengths is a part length, cut from like an offcut without becoming one" do
    @bar.move_stock(branch: @yard, quantity: 16, reason: "received")
    assert_equal [ 2, 4.0, [] ], rack(@yard)

    @bar.move_stock(branch: @yard, quantity: -3, reason: "sold")
    assert_equal [ 2, 1.0, [] ], rack(@yard)
    assert_equal "3 m cut from a 4 m part length, leaving a 1 m part length", @bar.stock_movements.where(branch: @yard, reason: "sold").sole.note
  end

  test "enough in all isn't enough: a piece longer than anything on the rack is refused, and nothing moves" do
    @bar.move_stock(branch: @main, quantity: -26.5, reason: "correction")
    Offcut.record(product: @bar, branch: @main, length: 2)
    Offcut.record(product: @bar, branch: @main, length: 1.5)
    assert_equal [ 0, 0.0, [ 1.5, 2.0 ] ], rack

    error = assert_raises(Product::NoPieceLongEnough) { sell 3 }
    assert_equal "No piece of Y12 steel bar at #{@main.name} is long enough to cut 3 m: the longest is 2 m", error.message
    assert_equal 3.5, @bar.stock_at(@main)
    assert_equal [ 1.5, 2.0 ], offcuts

    sell 2, 1.5
    assert_equal 0, @bar.stock_at(@main)
    assert_empty offcuts
    assert_equal [ "The 2 m offcut", "The 1.5 m offcut" ], notes
  end

  test "the till refuses a cut nothing is long enough for, when adding it and again at payment" do
    @bar.move_stock(branch: @main, quantity: -22, reason: "correction")   # one full length and a 2 m part length
    line = @sale.add(@bar, quantity: 8, cut_length: 4)
    assert_match "No piece of Y12 steel bar at #{@main.name} is long enough to cut 4 m: the longest is 2 m", line.errors.full_messages.to_sentence
    assert_empty @sale.lines.reload
    assert_equal [ 4, 2 ], accounts(:acme).stock_refusals.where(product: @bar).pluck(:quantity, :on_hand).flatten.map(&:to_i), "the owner hears what was asked for"

    assert_empty @sale.add(@bar, quantity: 4, cut_length: 4).errors
    @bar.move_stock(branch: @main, quantity: -3, reason: "sold")   # another till cuts 3 m off the last full length
    payment = @sale.pay(tender: "cash", tendered_cents: 100_000)
    assert_match "is long enough to cut 4 m: the longest is 3 m. Take it off the sale or sell fewer", payment.errors.full_messages.to_sentence
    assert @sale.reload.open?
  end

  test "a sale of cut lengths: the line says how it's cut, the ledger says from what, and a void puts the pieces back" do
    line = @sale.add(@bar, quantity: 7.5, cut_length: 2.5)
    assert_equal [ 3, "3 × 2.5 m", 150_000 ], [ line.pieces, line.cut_words, line.total_cents ]
    assert_equal "Y12 steel bar · 3 × 2.5 m", line.description
    assert_equal line.id, @sale.add(@bar, quantity: 2.5, cut_length: 2.5).id, "the same cut again adds to the line"
    assert_equal 4, line.reload.pieces
    assert_not_equal line.id, @sale.add(@bar, quantity: 1, cut_length: 1).id, "another length is its own line"

    @sale.pay(tender: "cash", tendered_cents: 300_000)
    assert @sale.reload.completed?
    assert_equal 19, @bar.stock_at(@main)
    assert_equal [ 3, 0.0, [ 1.0 ] ], rack, "four 2.5 m pieces from two lengths, and 1 m off one of the 1 m offcuts"
    assert_equal [ "Y12 steel bar" ] * 3, @sale.cutting_list.map { _1.first.name }
    assert_includes @sale.cutting_list.map(&:last), "2 × 2.5 m cut from a 6 m length, leaving a 3.5 m offcut"

    assert @sale.void(reason: "Wrong customer", refund_method: "cash")
    assert_equal 30, @bar.stock_at(@main)
    assert_equal [ 3, 0.0, [ 1.0, 1.0, 2.5, 2.5, 2.5, 2.5 ] ], rack, "cut steel comes back as the pieces it was cut into"
  end

  test "a line can't be cut longer than the product comes" do
    line = @sale.add(@bar, quantity: 7, cut_length: 7)
    assert_includes line.errors.full_messages, "Y12 steel bar comes in lengths of 6 m, so a piece can't be 7 m"
  end

  test "an offline till's sale goes through whatever the rack says" do
    @bar.move_stock(branch: @main, quantity: -27, reason: "correction")
    Offcut.record(product: @bar, branch: @main, length: 1)
    @bar.move_stock(branch: @main, quantity: -4, reason: "sold", allow_negative: true)

    assert_equal(-1, @bar.stock_at(@main))
    assert_empty offcuts, "nothing listed that isn't there"
    assert_equal "4 m: no piece on record was long enough", notes.last
  end

  test "stock leaving another way keeps the offcut list within what's there" do
    sell 2
    sell 4.5
    assert_equal [ 1.5, 4.0 ], offcuts

    @bar.move_stock(branch: @main, quantity: -(@bar.stock_at(@main) - 4.5), reason: "transfer_out")
    assert_equal [ 4.0 ], offcuts, "4.5 m left can't hold 5.5 m of offcuts: the shortest goes"
  end

  test "offcuts are kept right by hand: added from unlisted stock, scrapped out of stock" do
    offcut = Offcut.record(product: @bar, branch: @main, length: 2.2)
    assert offcut.persisted?
    assert_equal [ 4, 3.8, [ 2.2 ] ], rack
    assert_equal 30, @bar.stock_at(@main), "listing a piece doesn't change the stock"

    assert_includes Offcut.record(product: @bar, branch: @main, length: 6).errors.full_messages, "Length must be shorter than the 6 m it comes in"
    assert_match "is already listed", Offcut.record(product: @bar, branch: @yard, length: 1).errors.full_messages.to_sentence

    offcut.scrap
    assert_equal 27.8, @bar.stock_at(@main)
    assert_equal [ "2.2 m offcut scrapped" ], notes("cutting_waste")
    assert_empty offcuts
  end

  test "only measured, stock-tracked products are cut to length; clearing the length forgets the offcuts" do
    cement = products(:acme_cement)
    cement.stock_length = 6
    assert_not cement.valid?
    assert_match "sold by a measured unit", cement.errors[:stock_length].to_sentence

    @bar.scrap_below = 6
    assert_not @bar.valid?
    @bar.tracks_batches, @bar.scrap_below = true, 0.5
    assert_includes @bar.tap(&:valid?).errors[:stock_length], "can't be combined with batches or serial numbers"
    @bar.reload

    sell 2
    @bar.update!(stock_length: nil)
    assert_empty @bar.offcuts
    assert_equal 0, @bar.scrap_below
    assert_nothing_raised { @bar.move_stock(branch: @main, quantity: -3, reason: "sold") }
  end

  test "cutting is a feature that can't be switched off while products use it" do
    account = accounts(:acme)
    account.update!(features: account.features + [ "cutting" ])
    account.features -= [ "cutting" ]
    assert_not account.valid?
    assert_match "A product is sold cut from lengths", account.errors.full_messages.to_sentence
    assert_includes account.features_in_use, "cutting"
  end

  test "a quote says how it's cut, and the order arrives at the till cut the same way" do
    order = accounts(:acme).customer_orders.create!(branch: @main, customer: customers(:acme_contractor),
      lines_attributes: [ { account: accounts(:acme), product_code: "Y12", quantity: 7.5, cut_length: 2.5 } ])
    assert_equal "Y12 steel bar · 3 × 2.5 m", order.lines.sole.description

    bad = accounts(:acme).customer_orders.new(branch: @main, customer: customers(:acme_contractor),
      lines_attributes: [ { account: accounts(:acme), product_code: "Y12", quantity: 7, cut_length: 2.5 } ])
    assert_not bad.valid?
    assert_match "7 m of Y12 steel bar isn't a whole number of 2.5 m pieces", bad.errors.full_messages.to_sentence

    assert order.confirm
    assert order.load_into(@sale)
    line = @sale.reload.lines.sole
    assert_equal [ 7.5, 2.5, 3 ], [ line.quantity.to_f, line.cut_length.to_f, line.pieces ]

    @sale.pay(tender: "cash", tendered_cents: 200_000)
    assert @sale.reload.completed?
    assert_equal [ 3, 0.0, [ 1.0, 3.5 ] ], rack
    assert order.reload.collected?
  end

  test "an offline till's sale keeps how it was cut; a cut that makes no sense is sold by the metre" do
    sale = lambda do |quantity, cut_length|
      Sale.record_offline({ uuid: SecureRandom.uuid, receipt_number: "MAIN-OFF1-0001", happened_at: 2.minutes.ago.iso8601, shift_id: shifts(:acme_front_open).id,
        cashier_id: users(:amina).id, total_cents: (quantity * 20000).to_i, payments: [ { tender: "cash", tendered_cents: 500_000 } ],
        lines: [ { product_id: @bar.id, quantity: quantity.to_s, cut_length: cut_length&.to_s, unit_price_cents: 20000 } ] }, register: registers(:acme_front))
    end

    result = sale.(5, 2.5)
    assert_equal "recorded", result.status
    assert_equal [ 2, 2.5 ], result.sale.lines.sole.then { [ _1.pieces, _1.cut_length.to_f ] }
    assert_equal [ 4, 0.0, [ 1.0 ] ], rack

    assert_nil sale.(5, 9).sale.lines.sole.cut_length, "longer than it comes"
    assert_nil sale.(5, 2).sale.lines.sole.cut_length, "not a whole number of pieces"
    assert_equal 15, @bar.stock_at(@main)
  end

  test "the offline catalogue says what length a product comes in" do
    catalogue = PosCatalogue.new(shift: shifts(:acme_front_open), user: users(:amina)).as_json
    assert_equal 6.0, catalogue[:products].find { _1[:sku] == "Y12" }[:stock_length]
    assert_nil catalogue[:products].find { _1[:sku] == "CEM-50" }[:stock_length]
  end

  test "offcuts that no longer fit travel with a transfer, and are listed where it arrives or comes back" do
    sell 2
    sell 4.5
    assert_equal [ 1.5, 4.0 ], offcuts

    transfer = accounts(:acme).stock_transfers.create!(from_branch: @main, to_branch: @yard, lines_attributes: [ { product_code: "Y12", quantity: 22 } ])
    assert_equal 1.5, @bar.stock_at(@main).to_f

    gone = transfer.lines.sole.offcut_lengths.map(&:to_f)
    assert_equal [ 1.5, 4.0 ] - offcuts, gone
    assert gone.any?

    assert transfer.receive
    assert_equal gone, offcuts(@yard)
    assert_equal 22, @bar.stock_at(@yard)
  end

  test "a cancelled transfer puts its offcuts back" do
    sell 2
    transfer = accounts(:acme).stock_transfers.create!(from_branch: @main, to_branch: @yard, lines_attributes: [ { product_code: "Y12", quantity: 26 } ])
    assert_empty offcuts
    assert transfer.cancel
    assert_equal [ 4.0 ], offcuts
    assert_equal 28, @bar.stock_at(@main)
  end

  test "products are imported and exported with the length they come in" do
    result = accounts(:acme).product_imports.create!(branch: @main, filename: "steel.csv", csv: <<~CSV).tap(&:check)
      sku,name,price,unit,stock_length,scrap_below
      Y16,Y16 steel bar,300,Metre,12,0.5
      Y12,Y12 steel bar,200,Metre,5.8,
      BAD-1,Hinge,150,Piece,6,
      BAD-2,Flat bar,150,Metre,6,7
    CSV
    problems = result.problems.to_h { [ _1["line"], _1["messages"].to_sentence ] }
    assert_match "stock_length is for products sold by a measured unit", problems[4]
    assert_match "scrap_below must be shorter than stock_length", problems[5]

    result = accounts(:acme).product_imports.create!(branch: @main, filename: "steel.csv", csv: <<~CSV).tap(&:check)
      sku,name,price,unit,stock_length,scrap_below
      Y16,Y16 steel bar,300,Metre,12,0.5
      Y12,Y12 steel bar,200,Metre,5.8,
    CSV
    assert result.ready?, result.problems.inspect
    result.update!(status: :importing)
    result.run
    assert_equal [ 12, 0.5 ], accounts(:acme).products.find_by!(sku: "Y16").then { [ _1.stock_length.to_f, _1.scrap_below.to_f ] }
    assert_equal [ 5.8, 0 ], @bar.reload.then { [ _1.stock_length.to_f, _1.scrap_below.to_f ] }

    csv = CSV.parse(ProductCsv.new(accounts(:acme).products.where(sku: "Y16"), branch: @main).to_csv, headers: true)
    assert_equal [ "12", "0.5" ], csv.first.values_at("stock_length", "scrap_below")
  end
end
