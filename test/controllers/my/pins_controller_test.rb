require "test_helper"

class My::PinsControllerTest < ActionDispatch::IntegrationTest
  test "cashiers set their PIN with their password" do
    sign_in_as users(:carl)

    patch my_pin_path, params: { pin: "4321", password: "wrong" }
    assert_response :unprocessable_entity

    patch my_pin_path, params: { pin: "12", password: "password" }
    assert_response :unprocessable_entity

    patch my_pin_path, params: { pin: "4321", password: "password" }
    assert_redirected_to my_profile_path
    assert Account.without_isolation { memberships(:carl_acme).reload.authenticate_pin("4321") }
  end

  test "owners and managers can't have a PIN" do
    sign_in_as users(:amina)

    get edit_my_pin_path
    assert_response :forbidden
  end

  test "promoting someone clears their PIN" do
    Current.set(account: accounts(:acme)) { memberships(:carl_acme).update!(role: :manager) }

    assert_nil Account.without_isolation { memberships(:carl_acme).reload.pin_digest }
  end
end
