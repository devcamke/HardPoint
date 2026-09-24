require "test_helper"

class CatalogueSettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "each list can be managed" do
    post categories_path, params: { category: { name: "Paint", parent_id: categories(:acme_building).id } }
    post brands_path, params: { brand: { name: "Crown" } }
    post units_path, params: { unit: { name: "Gallon", abbreviation: "gal", fractional: "1" } }
    post tax_rates_path, params: { tax_rate: { name: "Reduced", rate: "8", default: "1" } }
    post price_lists_path, params: { price_list: { name: "Staff" } }

    Account.without_isolation do
      account = accounts(:acme)
      assert_equal "Building materials › Paint", account.categories.find_by!(name: "Paint").full_name
      assert account.brands.exists?(name: "Crown")
      assert account.units.find_by!(name: "Gallon").fractional?
      assert_equal [ "Reduced" ], account.tax_rates.where(default: true).pluck(:name), "only one default"
      assert account.price_lists.exists?(name: "Staff")
    end
  end

  test "in-use entries can't be removed" do
    delete unit_path(units(:acme_bag))
    follow_redirect!
    assert_select "#alert", /Cannot delete record because dependent products exist/
  end

  test "invalid input re-renders the list with errors" do
    post brands_path, params: { brand: { name: "Bamburi" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /Name has already been taken/
  end

  test "another shop's entries can't be edited" do
    get edit_category_path(categories(:bolt_tools))
    assert_response :not_found
  end

  test "cashiers can look but not change" do
    sign_in_as users(:carl)
    get categories_path
    assert_response :success
    post categories_path, params: { category: { name: "Nope" } }
    assert_response :forbidden
  end
end
