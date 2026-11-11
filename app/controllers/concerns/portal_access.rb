# The customer portal is opened from a link (PortalLink), without signing in. Each request finds the link by its
# token at this shop; an unknown, expired or taken-back link, or a shop that has switched the portal off, opens
# nothing. The pages hold a customer's account, so they're kept out of search engines, caches and referrers.
module PortalAccess
  extend ActiveSupport::Concern

  included do
    allow_unauthenticated_access
    allow_without_two_factor
    allow_while_locked
    before_action :set_portal_link
    after_action :keep_private
    layout "portal"
  end

  private
    def set_portal_link
      if Current.account.feature?(:customer_portal)
        @link = action_name == "show" && controller_name == "portals" ? PortalLink.open(params[:token], Current.account) : Current.account.portal_links.current.find_by(token: params[:token].to_s)
      end
      return render("portals/expired", status: :not_found) unless @link

      @customer = @link.customer
    end

    def keep_private
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["Cache-Control"] = "no-store"
    end
end
