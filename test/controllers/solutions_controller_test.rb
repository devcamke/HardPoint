require "test_helper"

class SolutionsControllerTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "each page about one job or market has its own title, description, questions and guides" do
    SolutionPage.all.each do |page|
      get "/#{page.slug}"
      assert_response :success

      assert_select "title", "#{page.title} · HardPoint"
      assert_select "meta[name=description][content=?]", page.description
      assert_select "link[rel=canonical][href=?]", "http://localhost/#{page.slug}"
      assert_select "h1", page.heading
      page.faqs.each { |question, _| assert_select "summary", question }
      page.help_articles.each { assert_select "a[href=?]", "/help/#{_1.slug}" }

      data = css_select("script[type='application/ld+json']").flat_map { JSON.parse(_1.text) }
      assert_equal %w[ SoftwareApplication FAQPage BreadcrumbList ], data.map { _1["@type"] }
      assert_equal page.title, data.last["itemListElement"].last["name"]
    end
  end

  test "every guide a page points to exists" do
    SolutionPage.all.each { |page| assert_equal page.help.size, page.help_articles.size, "#{page.slug} names a guide that isn't there" }
  end

  test "the public site says it's for Kenya, and every page links to the others" do
    get "/"
    assert_select "html[lang=en-KE]"
    assert_select "link[rel=alternate][hreflang=en-KE]"
    assert_select "meta[name='geo.region'][content=KE]"
    SolutionPage.all.each { assert_select "footer a[href=?]", "/#{_1.slug}" }
  end

  test "the East Africa page is honest about what works outside Kenya" do
    get "/east-africa"
    assert_select "li", text: /doesn't yet send sales to URA's EFRIS, TRA or RRA/
  end

  test "unknown pages aren't caught, and shop subdomains don't serve them" do
    get "/not-a-page"
    assert_response :not_found

    host! "acme.localhost"
    get "/kra-etims-pos"
    assert_not_equal 200, response.status
  end
end
