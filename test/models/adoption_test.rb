require "test_helper"

class AdoptionTest < ActiveSupport::TestCase
  setup do
    Account.without_isolation do
      accounts(:acme).update_columns(created_at: Adoption::SIMPLIFIED_ON.to_time + 1.day)
      accounts(:bolt).update_columns(created_at: Adoption::SIMPLIFIED_ON.to_time - 10.days)
    end
  end

  def sell_at_acme(on:)
    Account.without_isolation do
      Current.set(account: accounts(:acme), session: accounts(:acme).sessions.create!(user: users(:carl))) do
        sale = shifts(:acme_front_open).current_sale
        sale.add(products(:acme_nails))
        sale.pay(tender: "cash")
        sale.update_columns(completed_at: on)
      end
    end
  end

  def cohorts = Account.without_isolation { Adoption.new.first_sale_cohorts(today: Adoption::SIMPLIFIED_ON + 20) }

  test "time to first sale, for shops that joined before the change and since" do
    sell_at_acme(on: Adoption::SIMPLIFIED_ON.to_time + 4.days)
    before, since = cohorts

    assert_equal [ 1, 0, 0, nil ], [ before.shops, before.selling, before.within_week, before.median_days ]
    assert_equal [ 1, 1, 1, 3.0 ], [ since.shops, since.selling, since.within_week, since.median_days ]
  end

  test "a sale dated before signing up counts as selling on day 0" do
    sell_at_acme(on: Adoption::SIMPLIFIED_ON.to_time - 50.days)
    assert_equal 0, cohorts.last.median_days
  end
end
