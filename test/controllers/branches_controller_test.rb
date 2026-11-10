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

class BranchBoundManagerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation { memberships(:sara_acme).update!(role: "manager", branch: branches(:acme_main)) }
    sign_in_as users(:sara), account: accounts(:acme)
  end

  test "a manager bound to a branch looks after that branch and its tills, and no other" do
    get branches_path
    assert_select "td", text: branches(:acme_main).name
    assert_select "td", text: "Timber yard", count: 0
    assert_select "a", text: "Add branch", count: 0

    patch branch_path(branches(:acme_main)), params: { branch: { phone: "0700 000 000" } }
    assert_redirected_to branches_path

    patch branch_path(branches(:acme_yard)), params: { branch: { name: "Mine now" } }
    assert_response :not_found
    post branches_path, params: { branch: { name: "Westlands" } }
    assert_response :forbidden
    delete branch_path(branches(:acme_main))
    assert_response :forbidden

    get registers_path
    assert_select "td", text: registers(:acme_yard).name, count: 0
    patch register_path(registers(:acme_yard)), params: { register: { active: "0" } }
    assert_response :not_found
    post registers_path, params: { register: { name: "Back counter", branch_id: branches(:acme_yard).id } }
    assert_response :not_found
    assert Account.without_isolation { registers(:acme_yard).reload.active? }
  end
end
