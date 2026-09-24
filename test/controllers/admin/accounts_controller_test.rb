require "test_helper"

class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup { host! "admin.localhost" }

  test "administrators sign in with password and two-factor, then see every shop" do
    sign_in_as_administrator

    get admin_accounts_path
    assert_response :success
    assert_select "td a", "Acme Hardware"
    assert_select "td a", "Bolt & Nut Supplies"
  end

  test "shop staff can't sign in to admin" do
    post admin_session_path, params: { email_address: users(:amina).email_address, password: "password" }

    assert_redirected_to new_admin_session_path
    get admin_accounts_path
    assert_redirected_to new_admin_session_path
  end

  test "the password alone isn't enough" do
    post admin_session_path, params: { email_address: users(:ada).email_address, password: "password" }
    post admin_two_factor_path, params: { code: "000000" }

    get admin_accounts_path
    assert_redirected_to new_admin_session_path
  end

  test "a shop session doesn't open admin" do
    sign_in_as users(:amina)
    host! "admin.localhost"

    get admin_accounts_path
    assert_redirected_to new_admin_session_path
  end

  test "shop pages aren't served on the admin subdomain" do
    get "/branches"
    assert_response :not_found
  end

  test "impersonating a shop's staff member is time-boxed and recorded" do
    sign_in_as_administrator

    post admin_impersonations_path, params: { membership_id: memberships(:carl_acme).id }
    assert_match %r{\Ahttp://acme\.localhost/session/impersonation/new\?token=}, response.location

    use_account accounts(:acme)
    post session_impersonation_path, params: { token: Rack::Utils.parse_query(URI(response.location).query)["token"] }
    assert_redirected_to root_path

    follow_redirect!
    assert_select "h1", "Welcome, Carl Cashier"
    assert_select "div.bg-safety-500", /HardPoint support \(Ada Admin\)/
    assert Account.without_isolation { Event.exists?(action: "impersonation_started", creator: users(:carl)) }

    travel Session::IMPERSONATION_DURATION + 1.minute do
      get root_path
      assert_redirected_to new_session_path
    end
  end

  test "impersonation links expire and only work on their own shop" do
    token = Impersonation.new(administrator: users(:ada), membership: memberships(:carl_acme)).token

    use_account accounts(:bolt)
    post session_impersonation_path, params: { token: token }
    assert_redirected_to new_session_path

    use_account accounts(:acme)
    travel 2.minutes do
      post session_impersonation_path, params: { token: token }
      assert_redirected_to new_session_path
    end
  end

  private
    def sign_in_as_administrator
      host! "admin.localhost"
      post admin_session_path, params: { email_address: users(:ada).email_address, password: "password" }
      assert_redirected_to new_admin_two_factor_path
      post admin_two_factor_path, params: { code: current_code(users(:ada).two_factor_secret) }
      assert_redirected_to admin_root_path
    end
end
