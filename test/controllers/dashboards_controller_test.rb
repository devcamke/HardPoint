require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "requires signing in" do
    use_account accounts(:acme)
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows the shop's own figures" do
    sign_in_as users(:amina), account: accounts(:acme)

    get root_path

    assert_response :success
    assert_select "h1", "Welcome, Amina Owner"
    assert_select "p.text-3xl", "5", "active products"
    assert_select "p.text-3xl", "1", "the PVC pipe is below its reorder level"
  end
end
