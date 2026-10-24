require "test_helper"

class PromotionTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @cement, @nails = products(:acme_cement), products(:acme_nails)
  end

  def promote(**attributes)
    accounts(:acme).promotions.create!({ name: "Offer", starts_on: Date.current, ends_on: Date.current + 7 }.merge(attributes))
  end

  test "buy ten, get one free: every eleventh bag is free, and it's not a hand discount" do
    promote(name: "Cement week", kind: "buy_get", buy_quantity: 10, free_quantity: 1, product_ids: [ @cement.id ])
    sale = @shift.current_sale
    line = sale.add(@cement, quantity: 10)
    assert_equal 0, line.promotion_discount_cents, "ten bags: nothing free yet"

    line = sale.add(@cement, quantity: 12)
    assert_equal 2 * 800_00, line.promotion_discount_cents
    assert_equal 22 * 800_00 - 2 * 800_00, line.total_cents
    assert_equal "Cement week", line.promotion.name
    assert_not sale.reload.discount_needs_approval?, "promotions don't need a manager"
  end

  test "a percentage off by category; the better of it and the customer's price list" do
    promote(kind: "percent_off", percent_off: 10, category_ids: [ @cement.category_id ])
    sale = @shift.current_sale
    line = sale.add(@cement, quantity: 2)
    assert_equal 2 * 80_00, line.promotion_discount_cents

    sale.change_customer(customers(:acme_contractor)) # contractor price 760.00, promotion 720.00
    line.reload
    assert_equal 760_00, line.unit_price_cents
    assert_equal 2 * 40_00, line.promotion_discount_cents, "only the difference to their own price"
  end

  test "the best promotion wins; paused, other-branch and finished ones don't count" do
    promote(kind: "percent_off", percent_off: 5, product_ids: [ @nails.id ])
    best = promote(kind: "percent_off", percent_off: 20, product_ids: [ @nails.id ])
    promote(kind: "percent_off", percent_off: 50, product_ids: [ @nails.id ], active: false)
    promote(kind: "percent_off", percent_off: 60, product_ids: [ @nails.id ], branch_ids: [ branches(:acme_yard).id ])
    promote(kind: "percent_off", percent_off: 70, product_ids: [ @nails.id ], starts_on: Date.current - 10, ends_on: Date.yesterday)

    line = @shift.current_sale.add(@nails, quantity: 1)
    assert_equal best, line.promotion
  end

  test "quotes and the online store get percentages; results add up" do
    promotion = promote(kind: "percent_off", percent_off: 25, product_ids: [ @nails.id ])
    order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_walk_in),
      lines_attributes: [ { account: accounts(:acme), product_code: "NAIL-3", quantity: 2 } ])
    assert_equal [ 187_50, promotion ], [ order.lines.sole.unit_price_cents, order.lines.sole.promotion ]
    assert_equal [ promotion, 187_50 ], @nails.promotion_price

    sale = @shift.current_sale
    sale.add(@nails, quantity: 4)
    sale.pay(tender: "cash", tendered_cents: 1000_00)
    result = Promotion::Results.for([ promotion ])[promotion.id]
    assert_equal [ 1, 4, 250_00, 750_00 ], [ result.sales, result.units, result.saving_cents, result.takings_cents ]
  end

  test "needs targets that are the shop's, an offer, and sensible dates" do
    assert_not accounts(:acme).promotions.new(name: "X", kind: "percent_off", percent_off: 10, starts_on: Date.current, ends_on: Date.current).valid?
    bolt = Account.without_isolation { products(:bolt_hammer) }
    invalid = accounts(:acme).promotions.new(name: "X", kind: "buy_get", buy_quantity: 0, free_quantity: 1, product_ids: [ @cement.id ], starts_on: Date.current, ends_on: Date.yesterday)
    assert_not invalid.valid?
    assert_includes invalid.errors.attribute_names, :ends_on
    assert_includes invalid.errors.attribute_names, :buy_quantity
    assert_not accounts(:acme).promotions.new(name: "X", kind: "percent_off", percent_off: 10, product_ids: [ bolt.id ], starts_on: Date.current, ends_on: Date.current).valid?
  end

  # The same cases as the bundle test in test/javascript/offline_test.mjs.
  test "mix and match: any three for a price, across lines, dearest units first, saving shared by cost" do
    @pipe, @kit = products(:acme_pipe), products(:acme_plumbing_kit) # 1,200.00 and 2,500.00
    bundle = promote(name: "Plumbing three", kind: "bundle", bundle_quantity: 3, bundle_price: "4000", category_ids: [ @pipe.category_id ])
    assert_equal "Any 3 for KES 4,000.00", bundle.offer
    sale = @shift.current_sale

    pipes = sale.add(@pipe, quantity: 2)
    assert_equal 0, pipes.reload.promotion_discount_cents, "two isn't a bundle"

    kit = sale.add(@kit)
    pipes.reload
    assert_equal [ bundle, bundle ], [ pipes.promotion, kit.reload.promotion ]
    assert_equal [ 440_81, 459_19 ], [ pipes.promotion_discount_cents, kit.promotion_discount_cents ], "900.00 shared 2,400 : 2,500, the odd cent to the kit"
    assert_equal 4000_00, sale.reload.total_cents

    sale.add(@pipe, quantity: 2) # five units: one bundle, of the kit and two pipes; two pipes at full price
    assert_equal [ 440_81, 459_19 ], [ pipes.reload.promotion_discount_cents, kit.reload.promotion_discount_cents ]
    assert_equal 4000_00 + 2 * 1200_00, sale.reload.total_cents

    sale.add(@pipe) # six units: two bundles
    assert_equal 8000_00, sale.reload.total_cents

    sale.lines.find_by(product: @kit).destroy
    sale.recalculate
    assert_equal [ nil, 0 ], [ pipes.reload.promotion, pipes.promotion_discount_cents ], "three pipes cost less than the bundle: nothing off"
  end

  test "a bundle only takes lines from their own promotions when it saves more; hand discounts and packs stay out" do
    @pipe, @kit = products(:acme_pipe), products(:acme_plumbing_kit)
    bundle = promote(kind: "bundle", bundle_quantity: 3, bundle_price: "4000", category_ids: [ @pipe.category_id ])
    sale = @shift.current_sale
    pipes = sale.add(@pipe, quantity: 2)
    kit = sale.add(@kit)

    thirty = promote(name: "Thirty off", kind: "percent_off", percent_off: 30, category_ids: [ @pipe.category_id ])
    accounts(:acme).forget_running_promotions
    sale = Sale.find(sale.id)
    sale.lines.each(&:reprice).each(&:save!)
    sale.recalculate
    assert_equal [ thirty, thirty ], [ pipes.reload.promotion, kit.reload.promotion ], "1,470 off line by line beats 900 off as a bundle"

    thirty.update!(active: false)
    sale = Sale.find(sale.id)
    sale.lines.each(&:reprice).each(&:save!)
    sale.recalculate
    assert_equal bundle, kit.reload.promotion

    kit.update!(discount_cents: 100_00)
    sale.recalculate
    assert_equal [ nil, nil ], [ pipes.reload.promotion, kit.reload.promotion ], "with a hand discount the kit is out, and two pipes aren't a bundle"
  end
end
