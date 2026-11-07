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

  test "each public page tells search engines and link previews what it is" do
    get "/"
    assert_select "title", "HardPoint · Point of sale and stock control for hardware stores in Kenya"
    assert_select "link[rel=canonical][href=?]", "http://localhost/"
    assert_select "meta[property='og:image'][content*='dashboard']"
    assert_select "meta[name=robots]", count: 0
    types = css_select("script[type='application/ld+json']").flat_map { JSON.parse(_1.text).pluck("@type") }
    assert_equal %w[ Organization SoftwareApplication ], types

    get pricing_path
    assert_select "meta[name=description][content^=?]", "Starter KES 2,500, Business KES 6,500, and Enterprise KES 15,000 a month"
    faq = css_select("script[type='application/ld+json']").flat_map { JSON.parse(_1.text) }.find { _1["@type"] == "FAQPage" }
    assert_equal "What happens after the free trial?", faq["mainEntity"].first["name"]

    get help_article_path("selling", from: "search")
    assert_select "title", "Selling at the till · Help centre · HardPoint"
    assert_select "link[rel=canonical][href=?]", "http://localhost/help/selling"

    get help_path(q: "printer")
    assert_select "meta[name=robots][content=noindex]"
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
