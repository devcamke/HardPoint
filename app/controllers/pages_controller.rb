# The public site on the bare domain: what HardPoint does, what it costs, and how shop data is handled.
class PagesController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  layout "marketing"

  def home
    @plans = Plan.all
  end

  def pricing
    @plans = Plan.all
  end

  def privacy
  end

  def terms
    @company = Billing.company
  end

  def data_processing
    @company = Billing.company
  end

  def sla
  end

  # /.well-known/security.txt: where to report a vulnerability (RFC 9116).
  def security_txt
    expires_in 1.day, public: true
    render plain: <<~TEXT
      Contact: mailto:#{Rails.configuration.x.security_email}
      Expires: #{(Date.current.beginning_of_year + 1.year).to_time.utc.iso8601}
      Preferred-Languages: en, sw
      Canonical: #{security_txt_url(host: Rails.configuration.x.webhook_url_options[:host], protocol: Rails.configuration.x.webhook_url_options[:protocol])}
      Policy: #{terms_url(subdomain: false)}
    TEXT
  end

  def developers
    @api_host = "api.#{request.domain}#{request.port_string}"
  end
end
