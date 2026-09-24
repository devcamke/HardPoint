require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "the bare domain shows the public site, with the plans" do
    get "/"
    assert_response :success
    assert_select "h1", /The till, the stock and the books/
    assert_select "#plan_starter", /KES 2,500/
    assert_select "a[href=?]", new_signup_path(plan: "enterprise")
  end

  test "pricing and privacy" do
    get pricing_path
    assert_select "h1", "Pricing"
    assert_select "#plan_business", /15 staff logins/

    get privacy_path
    assert_select "h2", "Closing your account"
  end

  test "the help centre, and searching it" do
    get help_path
    assert_select "a[href=?]", help_article_path("offline")

    get help_path(q: "printer")
    assert_select "a[href=?]", help_article_path("tills-and-printers")
    assert_select "a[href=?]", help_article_path("offline"), count: 0

    get help_article_path("billing")
    assert_select "h1", "Plans, billing and read-only mode"

    get help_article_path("nope")
    assert_response :not_found
  end

  test "signing in asks which shop, then goes to that shop's sign-in" do
    get new_shop_lookup_path
    assert_response :success

    post shop_lookup_path, params: { subdomain: " ACME.localhost " }
    assert_redirected_to "http://acme.localhost/session/new"

    post shop_lookup_path, params: { subdomain: "nobody" }
    assert_response :unprocessable_entity
  end

  test "the public site isn't served on shop subdomains" do
    use_account accounts(:acme)
    get pricing_path
    assert_response :not_found
  end
end
