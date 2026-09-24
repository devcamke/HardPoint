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

  def developers
    @api_host = "api.#{request.domain}#{request.port_string}"
  end
end
