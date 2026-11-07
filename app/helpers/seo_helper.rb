# Structured data (schema.org JSON-LD) for the public site, so search engines can show HardPoint's prices,
# FAQs and help guides properly. Rails escapes <, > and & inside the JSON, so text can't end the script tag.
module SeoHelper
  def structured_data(*items)
    content_for :structured_data, tag.script(items.compact.to_json.html_safe, type: "application/ld+json")
  end

  def seo_organization
    { "@context": "https://schema.org", "@type": "Organization", name: "HardPoint", url: marketing_root_url,
      logo: "#{request.base_url}/icon.png", email: Rails.configuration.x.support[:email], areaServed: "KE",
      contactPoint: { "@type": "ContactPoint", contactType: "customer support", email: Rails.configuration.x.support[:email],
                      availableLanguage: "English", areaServed: "KE" } }
  end

  def seo_software(plans)
    { "@context": "https://schema.org", "@type": "SoftwareApplication", name: "HardPoint",
      applicationCategory: "BusinessApplication", applicationSubCategory: "Point of sale", operatingSystem: "Web browser",
      url: marketing_root_url, image: image_url("marketing/dashboard.png"),
      description: "Point of sale and stock control for hardware stores in Kenya, with M-Pesa, Airtel Money and KRA eTIMS. The till keeps selling offline.",
      offers: plans.map do |plan|
        { "@type": "Offer", name: plan.name, description: plan.blurb, price: format("%.2f", plan.price_cents / 100.0), priceCurrency: "KES",
          url: new_signup_url(plan: plan.key), availability: "https://schema.org/InStock",
          priceSpecification: { "@type": "UnitPriceSpecification", price: format("%.2f", plan.price_cents / 100.0), priceCurrency: "KES",
                                billingDuration: 1, billingIncrement: 1, unitCode: "MON", referenceQuantity: { "@type": "QuantitativeValue", value: 1, unitCode: "MON" } } }
      end }
  end

  def seo_faq(questions)
    { "@context": "https://schema.org", "@type": "FAQPage",
      mainEntity: questions.map { |question, answer| { "@type": "Question", name: question, acceptedAnswer: { "@type": "Answer", text: answer } } } }
  end

  def seo_help_article(article)
    [ { "@context": "https://schema.org", "@type": "TechArticle", headline: article.title, description: article.summary,
        articleSection: article.section, url: help_article_url(article), inLanguage: "en-KE",
        publisher: { "@type": "Organization", name: "HardPoint", logo: { "@type": "ImageObject", url: "#{request.base_url}/icon.png" } } },
      { "@context": "https://schema.org", "@type": "BreadcrumbList", itemListElement: [
        { "@type": "ListItem", position: 1, name: "HardPoint", item: marketing_root_url },
        { "@type": "ListItem", position: 2, name: "Help centre", item: help_url },
        { "@type": "ListItem", position: 3, name: article.title, item: help_article_url(article) } ] } ]
  end
end
