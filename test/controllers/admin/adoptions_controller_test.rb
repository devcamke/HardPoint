require "test_helper"

class Admin::AdoptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "admin.localhost"
    sign_in_as_administrator
  end

  test "shows the plan's measures across every shop" do
    Account.without_isolation do
      UsageCount.record("search:products", account: accounts(:acme))
      UsageCount.record("search:products", account: accounts(:bolt))
      UsageCount.record("reorder_draft_all", account: accounts(:acme))
      SupportRequest.create!(account: accounts(:acme), user: users(:carl), subject: "Where is the reorder list?", body: "It moved")
    end

    get admin_adoption_path

    assert_response :success
    assert_select "#first-sale tr", /Signed up since/
    assert_select "#shortcuts tr", /Search: opened a product\s*2\s*2/
    assert_select "#shortcuts tr", /Reorder: drafted every supplier's order at once\s*1\s*1/
    assert_select "#features tr", /Tool hire\s*1/
    assert_select "#lost", /1\s*in the last 30 days/
    assert_select "#lost li", /Where is the reorder list\?/
  end

  test "shop staff can't see it" do
    host! "acme.localhost"
    get "/adoption"
    assert_response :not_found
  end
end
