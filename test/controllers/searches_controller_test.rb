require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "finds products, customers and suppliers, with things to do with the best match" do
    get search_path(q: "pvc"), headers: { "Turbo-Frame" => "search_results" }

    assert_select "turbo-frame#search_results" do
      assert_select "h2", "Products"
      assert_select "a[href=?]", product_path(products(:acme_pipe), from: "search:products"), text: /PVC pipe 2 inch 6m/
      assert_select "h2", "Do something with PVC pipe 2 inch 6m"
      assert_select "a", /Order more/
    end
    assert_select "nav", 0, "the frame answer is just the results"
  end

  test "pages are found by their name and by the name they used to have" do
    get search_path(q: "reorder suggestions"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a[href=?]", reorder_list_path(from: "search:pages"), text: /Reorder/

    get search_path(q: "tax"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a[href=?]", tax_rates_path(from: "search:pages"), text: /Tax rates/
  end

  test "a document number opens that document" do
    order = Account.without_isolation { PurchaseOrder.create!(account: accounts(:acme), supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
      lines_attributes: [ { account: accounts(:acme), product: products(:acme_cement), quantity: 10, unit_cost_cents: 68_000 } ]) }

    get search_path(q: Account.without_isolation { order.reference }), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a[href=?]", purchase_order_path(order, from: "search:documents")
  end

  test "a scanned barcode goes straight to its product" do
    get search_path(q: "6161100420017")
    assert_redirected_to product_path(Account.without_isolation { Barcode.find_by!(code: "6161100420017").product })
  end

  test "results are limited to what this person may open" do
    sign_in_as users(:carl)
    get search_path(q: "kentube"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "h2", text: "Suppliers", count: 0

    get search_path(q: "pvc"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a", text: /Order more/, count: 0
  end

  test "the search page works without the popup" do
    get search_path(q: "cement")
    assert_response :success
    assert_select "input[name=q][value=cement]"
    assert_select "turbo-frame#search_results a", /Bamburi cement/
  end
end
