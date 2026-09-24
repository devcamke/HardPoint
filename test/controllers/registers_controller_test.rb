require "test_helper"

class RegistersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "index lists this shop's tills" do
    get registers_path

    assert_response :success
    assert_select "td", text: "Front counter"
    assert_select "td", text: "Counter 1", count: 0
  end

  test "create" do
    assert_difference -> { Account.without_isolation { accounts(:acme).registers.count } } do
      post registers_path, params: { register: { name: "Paint desk", branch_id: branches(:acme_main).id, active: "1" } }
    end

    assert_redirected_to registers_path
  end

  test "a till can't be attached to another shop's branch" do
    assert_no_difference -> { Account.without_isolation { Register.count } } do
      post registers_path, params: { register: { name: "Sneaky", branch_id: branches(:bolt_main).id } }
    end

    assert_response :not_found
  end

  test "another shop's tills can't be reached" do
    get edit_register_path(registers(:bolt_front))
    assert_response :not_found
  end

  test "cashiers can see tills but not change them" do
    sign_in_as users(:carl)

    get registers_path
    assert_response :success

    patch register_path(registers(:acme_front)), params: { register: { name: "Mine" } }
    assert_response :forbidden
  end
end
