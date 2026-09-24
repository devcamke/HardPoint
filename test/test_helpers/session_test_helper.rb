module SessionTestHelper
  # Signs in through the real sign-in form on the shop's subdomain (every fixture user's
  # password is "password"), so the session cookie is issued for that subdomain.
  def sign_in_as(user, account: Account.without_isolation { user.accounts.first })
    use_account account
    post session_path, params: { email_address: user.email_address, password: "password" }
    assert cookies[:session_id].present?, "Expected #{user.email_address} to be able to sign in to #{account.subdomain}"
  end

  def sign_out
    delete session_path
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
