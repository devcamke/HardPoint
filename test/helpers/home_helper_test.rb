require "test_helper"

class HomeHelperTest < ActionView::TestCase
  include CatalogueHelper

  Numbers = Struct.new(:account, :branch, :low_stock_count, :owed_to_us, :owed_by_us, :orders_ready_count, :deliveries_outstanding_count)

  setup do
    @dashboard = Numbers.new(accounts(:acme), nil, 3, { total: 50_000, overdue: 20_000, overdue_customers: 2 },
      { total: 0, overdue: 0, overdue_suppliers: 0 }, 1, 0)
  end

  test "rows are limited to what this person may act on" do
    in_acme do
      assert_equal %i[ low_stock customers_overdue orders_ready ], home_tasks(@dashboard, memberships(:amina_acme)).map(&:key)
      assert_equal %i[ low_stock orders_ready ], home_tasks(@dashboard, memberships(:sara_acme)).map(&:key)
      assert_equal "See which", home_tasks(@dashboard, memberships(:carl_acme)).first.action
    end
  end

  test "rows say how much and lead somewhere" do
    in_acme do
      overdue = home_tasks(@dashboard, memberships(:amina_acme)).find { _1.key == :customers_overdue }
      assert_equal "KES 200.00 overdue from 2 customers", overdue.title
      assert_equal receivables_path, overdue.path
    end
  end

  test "quick actions follow the role" do
    assert_equal [ "New product", "New quote", "Receive goods", "Count stock" ], home_quick_actions(memberships(:amina_acme)).map(&:first)
    assert_equal [ "New quote" ], home_quick_actions(memberships(:carl_acme)).map(&:first)
  end

  private
    def in_acme(&)
      Account.without_isolation { Current.set(account: accounts(:acme), &) }
    end
end
