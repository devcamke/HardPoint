require "test_helper"

class UsageTrackingTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  def counts = Account.without_isolation { UsageCount.where(account: accounts(:acme)).pluck(:name, :count).to_h }

  test "links on Home and in search results carry where they were followed from" do
    get root_path(branch_id: branches(:acme_main).id)
    assert_select "#task_low_stock a[href*='from=home%3Alow_stock']"
    assert_select "nav[aria-label='Quick actions'] a[href$='from=quick%3Anew_product']"

    get search_path(q: "pvc"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a[href$='from=search%3Aproducts']"
  end

  test "following a tagged link counts it" do
    get reorder_list_path(branch_id: branches(:acme_main).id, from: "home:low_stock")
    get product_path(products(:acme_pipe), from: "search:products")
    get product_path(products(:acme_pipe), from: "search:products")

    assert_equal({ "home:low_stock" => 1, "search:products" => 2 }, counts)
  end

  test "made-up names and other methods aren't counted" do
    get products_path(from: "anything")
    post products_path(from: "quick:new_product"), params: { product: { name: "" } }
    assert_empty counts
  end
end
