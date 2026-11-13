require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "the bare domain shows the public site, with the plans" do
    get "/"
    assert_response :success
    assert_select "h1", /Point of sale and stock control for hardware stores/
    assert_select "#plan_starter", /KES 2,500/
    assert_select "#plan_solo", /KES 1,500/
    assert_select "a[href=?]", new_signup_path(plan: "unlimited")
  end

  test "each public page tells search engines and link previews what it is" do
    get "/"
    assert_select "title", "HardPoint · Point of sale and stock control for hardware stores in Kenya"
    assert_select "link[rel=canonical][href=?]", "http://localhost/"
    assert_select "meta[property='og:image'][content*='dashboard']"
    assert_select "meta[name=robots]", count: 0
    types = css_select("script[type='application/ld+json']").flat_map { JSON.parse(_1.text).pluck("@type") }
    assert_equal %w[ Organization SoftwareApplication FAQPage ], types

    get pricing_path
    assert_select "meta[name=description][content^=?]", "Solo KES 1,500, Starter KES 2,500, Business KES 3,500, and Unlimited KES 5,000 a month"
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
    assert_select "h1", "One price for the whole shop."
    assert_select "#plan_business", /10 staff logins/
    assert_select "#plan_starter", /Unlimited products/
    assert_select "#plan_starter", /KES 25,000 a year/
    assert_select "#plan_starter", /A till is KES 300 and a branch KES 750/
    assert_select "#plan_unlimited", { text: /Need one more/, count: 0 }
    assert_select "#plan_business", /Recommended/
    assert_select "input[type=radio][name=billing][value=yearly]"
    assert_select "#setup", /from KES 15,000.00/

    get privacy_path
    assert_select "h2", "Closing your account"
    assert_select "h2", "If something goes wrong"
  end

  test "the terms, data processing terms and service level agreement" do
    get terms_path
    assert_select "h1", "Terms of service"
    assert_select "h2", "The free trial"
    assert_select "p", /#{Plan::GRACE.inspect} after its date makes the shop read-only/
    assert_select "p", /HardPoint Ltd, Nairobi, Kenya/

    get data_processing_path
    assert_select "h1", "Data processing terms"
    assert_select "p", /within 72 hours/
    assert_select "p", /Airtel Africa \(Airtel Money\)/

    get sla_path
    assert_select "h1", "Service level agreement"
    assert_select "p", /99\.9% of each calendar month/
    assert_select "td", /Within 2 hours/

    get pricing_path
    assert_select "summary", "Is there an uptime guarantee?"
    assert_select "footer a[href=?]", sla_path
    assert_select "footer a[href=?]", terms_path

    get "/sitemap.xml"
    assert_match "http://localhost/sla", response.body
  end

  test "security.txt says where to report a vulnerability, on every host" do
    get "/.well-known/security.txt"
    assert_response :success
    assert_match "Contact: mailto:security@hardpoint.app", response.body
    assert_match(/Expires: \d{4}-\d{2}-\d{2}T/, response.body)

    use_account accounts(:acme)
    get "/.well-known/security.txt"
    assert_response :success
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

  test "the landing page says how a shop's data is kept, and answers whether it's safe" do
    get marketing_root_path
    assert_select "section#security h2", "Safe, private, and yours."
    assert_select "section#security li", 6
    assert_select "section#security a[href='#{privacy_path}']"
    assert_match "Is my shop&#39;s data safe?", response.body
    assert_select "a[href='#{help_article_path("fundis")}']"
    assert_select "a[href='#{help_article_path("material-calculator")}']"
  end

  test "the landing page's example till can show what changes offline, in words true of the offline till" do
    get marketing_root_path
    assert_select "[data-controller=offline-demo]" do
      # Hidden until the controller connects, so it never sits there doing nothing.
      assert_select "button[hidden][data-action='offline-demo#toggle']", /Pull the plug/
      assert_select "[data-offline-text*='M-Pesa code typed in']"
      assert_select "[data-offline-text*='-OFF1-']"
    end
    assert_select "dialog [data-controller=walkthrough], dialog .walkthrough", minimum: 1
  end

  test "every guide the landing page links to exists, and the nav's Features link has somewhere to land" do
    get marketing_root_path
    assert_select "#features"
    slugs = css_select("a[href^='/help/']").map { _1["href"].delete_prefix("/help/") }.uniq
    assert_operator slugs.size, :>=, 15
    slugs.each { |slug| assert HelpArticle.find(slug), "No help article #{slug}" }
  end

  test "the landing page shows how the counter is watched, and HardPoint on staff's and customers' phones" do
    get marketing_root_path
    assert_select "#counter li", minimum: 6
    assert_select "#counter .lp-mail", /voided 7 sales \(usually about 1 a day\)/
    assert_select "#phones img[src*='phone-stock-count']"
    assert_select "#phones img[src*='phone-customer-portal']"
    assert_select ".lp-works li", 8
  end

  test "the public site follows the device's light or dark setting" do
    get marketing_root_path
    assert_select "meta[name=color-scheme][content=?]", "light dark"
    assert_select "meta[name=theme-color][media*=dark]"
    assert_select "body.lp-site"
  end

  test "the landing page's prices come from the plans" do
    get marketing_root_path
    Plan.all.each do |plan|
      assert_select "#plan_#{plan.key}", /KES #{ActiveSupport::NumberHelper.number_to_delimited(plan.price_cents / 100)}/
      assert_select "#plan_#{plan.key} a[href=?]", new_signup_path(plan: plan.key)
    end
    assert_select ".lp-sticky", /KES 1,500/
    assert_select "#plan_business", /Recommended/
    assert_select "#plan_unlimited", /Unlimited branches/
  end
end
