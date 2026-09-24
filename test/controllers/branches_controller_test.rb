require "test_helper"

class BranchesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina), account: accounts(:acme) }

  test "index only lists this shop's branches" do
    get branches_path

    assert_response :success
    assert_select "td", text: "Timber yard"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(branches(:bolt_main))}", count: 0
  end

  test "create" do
    assert_difference -> { Account.without_isolation { accounts(:acme).branches.count } } do
      post branches_path, params: { branch: { name: "Westlands", address: "Waiyaki Way" } }
    end

    assert_redirected_to branches_path
  end

  test "update" do
    patch branch_path(branches(:acme_yard)), params: { branch: { name: "Timber & steel yard" } }

    assert_redirected_to branches_path
    assert_equal "Timber & steel yard", Account.without_isolation { branches(:acme_yard).reload.name }
  end

  test "another shop's branches can't be reached" do
    get edit_branch_path(branches(:bolt_main))
    assert_response :not_found

    patch branch_path(branches(:bolt_main)), params: { branch: { name: "Hijacked" } }
    assert_response :not_found

    delete branch_path(branches(:bolt_main))
    assert_response :not_found

    assert_equal "Main branch", Account.without_isolation { branches(:bolt_main).reload.name }
  end

  test "cashiers can see branches but not change them" do
    sign_in_as users(:carl), account: accounts(:acme)

    get branches_path
    assert_response :success

    post branches_path, params: { branch: { name: "Nope" } }
    assert_response :forbidden
  end
end
