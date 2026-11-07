require "test_helper"

class SeoControllerTest < ActionDispatch::IntegrationTest
  test "search engines may read the public site, and are pointed at its sitemap" do
    use_apex_domain
    get "/robots.txt"
    assert_response :success
    assert_includes response.body, "Allow: /\n"
    assert_includes response.body, "Disallow: /shop_lookup"
    assert_includes response.body, "Sitemap: http://localhost/sitemap.xml"
  end

  test "on a shop's subdomain only its online store is for search engines" do
    host! "acme.localhost"
    get "/robots.txt"
    assert_equal "User-agent: *\nAllow: /store\nDisallow: /\n", response.body
  end

  test "admin and the API are kept out of search engines" do
    %w[ admin api ].each do |subdomain|
      host! "#{subdomain}.localhost"
      get "/robots.txt"
      assert_equal "User-agent: *\nDisallow: /\n", response.body
    end
  end

  test "the sitemap lists the public pages and every help guide" do
    use_apex_domain
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, "<loc>http://localhost/pricing</loc>"
    HelpArticle.all.each { assert_includes response.body, "<loc>http://localhost/help/#{_1.slug}</loc>" }

    host! "acme.localhost"
    get "/sitemap.xml"
    assert_response :not_found
  end
end
