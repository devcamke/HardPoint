# The shop's public online store: no sign-in, the shop from the subdomain as everywhere else. It stays
# open to browse while the shop is read-only, but doesn't take orders then.
class Store::BaseController < ApplicationController
  allow_unauthenticated_access
  allow_without_two_factor
  allow_while_locked
  layout "store"

  before_action :set_storefront
  helper_method :storefront, :cart

  private
    attr_reader :storefront

    def set_storefront
      @storefront = Current.account.storefront
      render "store/closed", status: :not_found, layout: false unless @storefront&.enabled?
    end

    def cart
      @cart ||= Storefront::Cart.new(storefront, cart_items)
    end

    # A plain hash in the session; written back so the cookie keeps the change.
    def cart_items
      @cart_items ||= (session[:store_cart] || {}).to_h.transform_keys(&:to_s)
    end

    def save_cart
      session[:store_cart] = cart_items
    end

    def require_taking_orders
      redirect_to store_cart_path, alert: "#{Current.account.name} isn't taking orders online right now. Please call us." unless storefront.taking_orders?
    end
end
