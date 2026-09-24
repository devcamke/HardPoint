# "Sign in" on the public site: each shop signs in on its own web address, so ask which one.
class ShopLookupsController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  rate_limit to: 20, within: 1.minute, only: :create, with: -> { redirect_to new_shop_lookup_path, alert: "Try again in a minute." }
  layout "marketing"

  def new
  end

  def create
    subdomain = params[:subdomain].to_s.strip.downcase.delete_prefix("https://").delete_prefix("http://").split(".").first.to_s

    if subdomain.present? && Account.exists?(subdomain: subdomain)
      redirect_to new_session_url(subdomain: subdomain), allow_other_host: true
    else
      flash.now[:alert] = "There's no shop at that address. Check the web address from your welcome email."
      render :new, status: :unprocessable_entity
    end
  end
end
