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

  test "owners see a switched-off webhook and a failed backup" do
    in_acme do
      Current.set(user: users(:amina)) do
        accounts(:acme).webhook_endpoints.create!(url: "https://hooks.example.com/x", event_types: %w[ sale.completed ],
          disabled_at: Time.current, disabled_reason: "25 deliveries in a row failed")
        accounts(:acme).account_backups.create!(kind: "manual", status: "failed", requested_by: users(:amina), failure: "bucket said no")
      end

      tasks = home_tasks(@dashboard, memberships(:amina_acme))
      webhooks = tasks.find { _1.key == :webhooks_disabled }
      assert_equal "1 webhook endpoint switched off", webhooks.title
      assert_equal developers_path, webhooks.path
      assert_equal account_data_path, tasks.find { _1.key == :backup_failed }.path

      assert_not_includes home_tasks(@dashboard, memberships(:sara_acme)).map(&:key), :webhooks_disabled, "only owners manage them"
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
