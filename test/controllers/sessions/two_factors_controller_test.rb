require "test_helper"

class Sessions::TwoFactorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = enable_two_factor_for(users(:amina))
    use_account accounts(:acme)
  end

  test "a password alone doesn't sign in someone with two-factor on" do
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }

    assert_redirected_to new_session_two_factor_path
    assert_nil cookies[:session_id]
  end

  test "the right code completes sign-in" do
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }
    post session_two_factor_path, params: { code: current_code(@secret) }

    assert_redirected_to root_url
    assert cookies[:session_id].present?
  end

  test "a wrong code doesn't" do
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }
    post session_two_factor_path, params: { code: "000000" }

    assert_redirected_to new_session_two_factor_path
    assert_nil cookies[:session_id]
  end

  test "the challenge expires" do
    post session_path, params: { email_address: users(:amina).email_address, password: "password" }

    travel 11.minutes do
      post session_two_factor_path, params: { code: current_code(@secret) }
    end

    assert_redirected_to new_session_path
  end

  test "there's no challenge without the password step" do
    get new_session_two_factor_path
    assert_redirected_to new_session_path
  end
end
