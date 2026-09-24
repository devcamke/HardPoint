module SessionTestHelper
  # Signs in through the real sign-in form on the shop's subdomain (every fixture user's
  # password is "password"), answering the two-factor challenge when the user has it on.
  def sign_in_as(user, account: Account.without_isolation { user.accounts.first }, two_factor_secret: nil)
    use_account account
    post session_path, params: { email_address: user.email_address, password: "password" }

    if two_factor_secret
      post session_two_factor_path, params: { code: current_code(two_factor_secret) }
    end

    assert cookies[:session_id].present?, "Expected #{user.email_address} to be able to sign in to #{account.subdomain}"
  end

  def sign_out
    delete session_path
  end

  # Platform administrators sign in on admin.<domain> with a password and two-factor code.
  def sign_in_as_administrator(user = users(:ada))
    host! "admin.localhost"
    post admin_session_path, params: { email_address: user.email_address, password: "password" }
    assert_redirected_to new_admin_two_factor_path
    post admin_two_factor_path, params: { code: current_code(user.two_factor_secret) }
    assert_redirected_to admin_root_path
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
