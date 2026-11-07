require "test_helper"

class UsageCountTest < ActiveSupport::TestCase
  setup { Current.account = accounts(:acme) }

  test "counts a shortcut once per use, in one row per shop, name and day" do
    3.times { UsageCount.record("search:products") }
    UsageCount.record("home:low_stock")

    assert_equal({ "search:products" => 3, "home:low_stock" => 1 }, UsageCount.where(on: Date.current).pluck(:name, :count).to_h)
  end

  test "only names on the list are counted" do
    [ "search:anything", "home:Low Stock", "<script>", "", nil, "reorder_draft_all; DROP" ].each { UsageCount.record(_1) }
    assert_equal 0, UsageCount.count
  end

  test "each shop only sees its own counts" do
    UsageCount.record("quick:new_product")
    UsageCount.record("quick:new_product", account: accounts(:bolt))
    assert_equal 1, Account.without_isolation { UsageCount.count }, "a shop can't write another shop's counts"

    Account.without_isolation { UsageCount.record("quick:new_product", account: accounts(:bolt)) }
    assert_equal 1, UsageCount.count
    assert_equal 2, Account.without_isolation { UsageCount.count }
  end
end
