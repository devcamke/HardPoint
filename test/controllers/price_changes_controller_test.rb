require "test_helper"

class PriceChangesControllerTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)

  test "preview every new price, then apply" do
    sign_in_as users(:amina)
    get products_path
    assert_select "a[href='#{new_price_change_path}']", "Change prices"

    params = { price_change: { target: "category:#{categories(:acme_building).id}", kind: "percent", change: "8", round_to: "500",
                               include_packs: "1", include_price_lists: "0" } }
    get new_price_change_path(params)
    assert_select "#preview h2", /1 price will change · Building materials, up 8%/
    assert_select "#preview td", "KES 865.00"
    assert_equal 80000, acme { products(:acme_cement).reload.price_cents }, "a preview changes nothing"

    post price_changes_path, params: params
    assert_redirected_to products_path
    assert_equal 86500, acme { products(:acme_cement).reload.price_cents }
    assert_equal 76000, acme { price_list_items(:acme_cement_contractor).reload.price_cents }

    get events_path
    assert_select "p", /changed 1 product price \(Building materials, up 8%\)/
  end

  test "cashiers can't change prices" do
    sign_in_as users(:carl)
    get new_price_change_path
    assert_response :forbidden
  end
end
