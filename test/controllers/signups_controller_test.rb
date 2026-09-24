require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "new, with the plan chosen on the pricing page" do
    get new_signup_path(plan: "starter")
    assert_response :success
    assert_select "h1", "Open your shop"
    assert_select "input[type=radio][value=starter][checked]"
  end

  test "create opens the shop on a trial of the chosen plan and sends the owner to its subdomain" do
    assert_difference -> { Account.count } do
      post signup_path, params: { signup: { shop_name: "Mjengo Hardware", subdomain: "mjengo", owner_name: "Wanjiru",
        email_address: "wanjiru@mjengo.test", password: "a long password", plan: "starter" } }
    end

    account = Account.find_by!(subdomain: "mjengo")
    assert_equal [ "starter", "trialing" ], [ account.plan, account.subscription_status ]
    assert_in_delta 30.days.from_now, account.trial_ends_at, 1.minute

    assert_redirected_to "http://mjengo.localhost/session/new?email_address=wanjiru%40mjengo.test"
  end

  test "create with invalid details" do
    assert_no_difference -> { Account.count } do
      post signup_path, params: { signup: { shop_name: "Clash", subdomain: "acme", owner_name: "Eve",
        email_address: "eve@clash.test", password: "a long password" } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation", /Subdomain has already been taken/
  end

  test "signup isn't served on shop subdomains" do
    use_account accounts(:acme)
    get new_signup_path
    assert_response :not_found
  end
end
