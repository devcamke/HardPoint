require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "requires signing in" do
    use_account accounts(:acme)
    get root_path
    assert_redirected_to new_session_path
  end

  test "staff without reports see the shop at a glance" do
    sign_in_as users(:carl), account: accounts(:acme)

    get root_path

    assert_response :success
    assert_select "h1", "Welcome, Carl Cashier"
    assert_select "p.text-3xl", "5", "active products"
    assert_select "p.text-3xl", "1", "the PVC pipe is below its reorder level"
    assert_select "turbo-cable-stream-source", 0
  end
end
