require "test_helper"

class My::TwoFactorsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "setting up two-factor" do
    get new_my_two_factor_path
    assert_response :success
    assert_select "svg[role=img]"

    post my_two_factor_path, params: { code: current_code(session[:pending_two_factor_secret]) }
    assert_redirected_to my_recovery_codes_path

    follow_redirect!
    assert_select "ul.font-mono li", count: User::TwoFactor::RECOVERY_CODE_COUNT

    get my_recovery_codes_path
    assert_redirected_to my_profile_path, "Recovery codes are only shown once"
    assert users(:amina).reload.two_factor_enabled?
    assert Account.without_isolation { Event.exists?(action: "two_factor_enabled", creator: users(:amina)) }
  end

  test "turning it off needs the password and a code" do
    enable_two_factor_for(users(:amina))

    delete my_two_factor_path, params: { password: "wrong", code: "aaaaa-11111" }
    assert users(:amina).reload.two_factor_enabled?

    delete my_two_factor_path, params: { password: "password" }
    assert users(:amina).reload.two_factor_enabled?

    recovery_code = users(:amina).two_factor_recovery_codes.split("\n").first
    delete my_two_factor_path, params: { password: "password", code: recovery_code }
    assert_not users(:amina).reload.two_factor_enabled?
  end

  test "a shop can require it for owners and managers" do
    Account.without_isolation { accounts(:acme).update!(require_two_factor_for_managers: true) }

    get root_path
    assert_redirected_to new_my_two_factor_path

    sign_in_as users(:carl)
    get root_path
    assert_response :success
  end
end
