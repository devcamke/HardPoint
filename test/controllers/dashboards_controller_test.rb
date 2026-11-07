require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "requires signing in" do
    use_account accounts(:acme)
    get root_path
    assert_redirected_to new_session_path
  end

  test "cashiers start at the till, with their own day underneath" do
    sign_in_as users(:carl), account: accounts(:acme)

    get root_path

    assert_response :success
    assert_select "h1", "Hi Carl"
    assert_select "a[href='#{pos_path}']", /start selling/
    assert_select "a[href='#{reorder_list_path}'] p.text-2xl", "1", "the PVC pipe is below its reorder level"
    assert_select "turbo-cable-stream-source", 0
    assert_select "#needs-you", 0
  end

  test "owners see what needs them today, each with the button that does it" do
    sign_in_as users(:amina)

    get root_path(branch_id: branches(:acme_main).id)

    assert_select "#needs-you", /Needs you today/
    assert_select "#task_low_stock", /1 product running low/ do
      assert_select "a[href=?]", reorder_list_path(branch_id: branches(:acme_main).id), text: "Order them"
    end
    assert_select "nav[aria-label='Quick actions'] a", text: "New product"
  end

  test "a row goes away once there's nothing to do" do
    Account.without_isolation { products(:acme_pipe).update!(reorder_level: 0) }
    sign_in_as users(:amina)

    get root_path(branch_id: branches(:acme_main).id)

    assert_select "#needs-you"
    assert_select "#task_low_stock", 0
  end

  test "a counter computer set to open straight into selling skips Home for cashiers" do
    Account.without_isolation { registers(:acme_front).update!(opens_till: true) }
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }

    get root_path
    assert_redirected_to pos_path

    get root_path(home: 1)
    assert_response :success, "the till's logo still reaches Home"
  end

  test "owners still get Home on a computer set to open straight into selling" do
    Account.without_isolation { registers(:acme_front).update!(opens_till: true) }
    sign_in_as users(:amina)
    post pos_till_path, params: { register_id: registers(:acme_front).id }

    get root_path
    assert_response :success
  end
end
