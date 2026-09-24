require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  test "owners can change shop settings" do
    sign_in_as users(:amina), account: accounts(:acme)

    patch account_path, params: { account: { name: "Acme Hardware & Paints", time_zone: "Pretoria", currency: "ZAR" } }

    assert_redirected_to edit_account_path
    assert_equal [ "Acme Hardware & Paints", "Pretoria", "ZAR" ], accounts(:acme).reload.values_at(:name, :time_zone, :currency)
  end

  test "the subdomain can't be changed from settings" do
    sign_in_as users(:amina), account: accounts(:acme)

    patch account_path, params: { account: { subdomain: "bolt" } }

    assert_equal "acme", accounts(:acme).reload.subdomain
  end

  test "only owners can change shop settings" do
    sign_in_as users(:carl), account: accounts(:acme)

    get edit_account_path
    assert_response :forbidden
  end
end
