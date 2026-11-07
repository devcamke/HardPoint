# What search engines may read, and the list of public pages for them. The public site, help and signup on the
# bare domain are for everyone; on a shop's own subdomain only its online store is, since everything else there
# is behind a sign-in; the admin and API subdomains aren't for search engines at all.
class SeoController < ActionController::Base
  def robots
    rules = if request.subdomain.blank?
      [ "Allow: /", "Disallow: /shop_lookup", "Sitemap: #{sitemap_url}" ]
    elsif request.subdomain.in?(%w[ admin api ])
      [ "Disallow: /" ]
    else
      [ "Allow: /store", "Disallow: /" ]
    end
    expires_in 1.day, public: true
    render plain: [ "User-agent: *", *rules ].join("\n") + "\n"
  end

  def sitemap
    return head :not_found if request.subdomain.present?

    @urls = [ marketing_root_url, pricing_url, new_signup_url, help_url, *HelpArticle.all.map { help_article_url(_1) },
              developer_docs_url, privacy_url ]
    expires_in 1.day, public: true
    render formats: :xml
  end
end
