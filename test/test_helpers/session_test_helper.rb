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
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
