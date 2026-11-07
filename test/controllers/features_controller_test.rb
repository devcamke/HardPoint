require "test_helper"

class FeaturesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "switching features off takes them out of the menus and Settings" do
    get features_path
    assert_select "input[type=checkbox][name='account[features][]'][value=tool_hire][checked]"

    patch features_path, params: { account: { features: [ "", "deliveries", "promotions" ] } }
    assert_redirected_to features_path
    assert_equal %w[ deliveries promotions ], Account.without_isolation { accounts(:acme).reload.features }
    assert Account.without_isolation { accounts(:acme).features_reviewed_at }

    get sales_path
    assert_select "nav [aria-label='Sell menu'] a", text: "Promotions"
    assert_select "nav [aria-label='Sell menu'] a", text: "Tool hire", count: 0
    get customers_path
    assert_select "nav [aria-label='Customers menu'] a", text: "Jobs", count: 0
    get products_path
    assert_select "nav [aria-label='Stock menu'] a", text: "Expiry", count: 0
    get settings_path
    %w[ Currencies Developers ].each { assert_select "a p", text: _1, count: 0 }
    get new_product_path
    assert_select "input[name='product[serialized]']", 0
  end

  test "a feature in use can't be switched off, and the page says why" do
    Account.without_isolation { products(:acme_nails).update!(serialized: true) }

    patch features_path, params: { account: { features: [ "" ] } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /Serial numbers can't be switched off/
    assert Account.without_isolation { accounts(:acme).reload.feature?(:serial_numbers) }
  end

  test "only the owner chooses features" do
    sign_in_as users(:sara)
    get features_path
    assert_response :forbidden
  end
end
