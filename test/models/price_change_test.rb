require "test_helper"

class PriceChangeTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  def change(**attributes) = PriceChange.new(account: accounts(:acme), **attributes)

  test "by a percentage or an amount, up or down, rounded, never below zero" do
    assert_equal 86400, change(kind: "percent", change: 8).new_price(80000)
    assert_equal 86500, change(kind: "percent", change: 8, round_to: 500).new_price(80000)
    assert_equal 85000, change(kind: "amount", change: 50).new_price(80000)
    assert_equal 72000, change(kind: "percent", change: -10).new_price(80000)
    assert_equal 0, change(kind: "amount", change: -900).new_price(80000)
  end

  test "a category takes in its subcategories" do
    pipes = accounts(:acme).categories.create!(name: "Pipes", parent: categories(:acme_plumbing))
    products(:acme_pipe).update!(category: pipes)

    assert_equal %w[ PVC-2 KIT-PLB ].sort, change(target: "category:#{categories(:acme_plumbing).id}").products.pluck(:sku).sort
  end

  test "packs with their own price and price-list prices move with the product unless left out" do
    rows = change(target: "category:#{categories(:acme_building).id}", kind: "percent", change: 10).rows
    assert_equal [ 88000, 83600 ], rows.map(&:new_cents).first(2), "cement, then its contractor price"
    assert rows.any? { _1.record.is_a?(PriceListItem) }

    only_products = change(target: "category:#{categories(:acme_building).id}", kind: "percent", change: 10, include_price_lists: false).rows
    assert only_products.all? { _1.record.is_a?(Product) }

    screws = change(target: "category:#{categories(:acme_fasteners).id}", kind: "percent", change: 10, include_price_lists: false).rows
    pack = screws.find { _1.record == product_units(:acme_screws_box) }
    assert_equal [ 40000, 44000 ], [ pack.old_cents, pack.new_cents ]
    assert_not change(target: "category:#{categories(:acme_fasteners).id}", kind: "percent", change: 10, include_packs: false).rows.any? { _1.record.is_a?(ProductUnit) }
  end

  test "applying changes every price at once and leaves one line in the activity log" do
    change = change(target: "category:#{categories(:acme_building).id}", kind: "amount", change: 50, round_to: 1000)
    assert change.valid?

    assert_difference -> { accounts(:acme).account_events.where(action: "prices_changed").count } do
      assert_equal 3, change.apply
    end
    assert_equal 85000, products(:acme_cement).reload.price_cents
    assert_equal 81000, price_list_items(:acme_cement_contractor).reload.price_cents
  end

  test "it says what's missing" do
    change = change(target: "", kind: "percent", change: 0)
    assert_not change.valid?
    assert_includes change.errors.full_messages, "Target choose which products"
    assert_not change(target: "all", kind: "percent", change: -100).valid?
  end
end
