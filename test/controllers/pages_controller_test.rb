require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "the bare domain shows the public site, with the plans" do
    get "/"
    assert_response :success
    assert_select "h1", /Point of sale and stock control for hardware stores/
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

  test "the help centre searches the guides' text, not only their titles" do
    get help_path(q: "Group By")
    assert_select "a[href=?]", help_article_path("getting-around")
    assert_select "a[href=?]", help_article_path("buying-from-suppliers")

    get help_path(q: "zzzz")
    assert_select "p", /No guides mention "zzzz"/
  end

  test "every help article renders, and links on to the next and related guides" do
    HelpArticle.all.each do |article|
      get help_article_path(article)
      assert_response :success
      assert_select "h1", article.title
    end

    get help_article_path("getting-started")
    assert_select "a[href=?]", help_article_path("getting-around"), text: /Finding your way around/
    assert_select "a[href=?]", help_article_path("tills-and-printers")
  end

  test "help articles' related guides exist" do
    HelpArticle.all.each { |article| assert_nothing_raised { article.related_articles } }
    assert_equal HelpArticle::SECTIONS.sort, HelpArticle.all.map(&:section).uniq.sort
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
