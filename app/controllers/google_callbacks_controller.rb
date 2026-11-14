# Where Google sends people back after "Sign in with Google", on the bare domain (the one address Google is
# told about). Nobody is signed in here: the address Google vouched for is handed on to the shop the sign-in
# started from, which decides (GoogleSignIn, Sessions::GooglesController).
class GoogleCallbacksController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  rate_limit to: 30, within: 3.minutes, with: -> { redirect_to new_shop_lookup_path, alert: "Try again later." }

  def show
    handoff = GoogleSignIn.exchange(code: params[:code], state: params[:state], redirect_uri: google_callback_url)
    redirect_to session_google_url(subdomain: handoff.subdomain, token: handoff.token), allow_other_host: true
  rescue GoogleSignIn::Refused, JsonHttp::Unreachable => error
    Rails.logger.info "Google sign-in refused: #{error.message}"

    # Back to the shop it started from when we can tell (someone who pressed Cancel at Google), which says it didn't work.
    if (subdomain = GoogleSignIn.subdomain_from(params[:state])) && Account.exists?(subdomain: subdomain)
      redirect_to session_google_url(subdomain: subdomain), allow_other_host: true
    else
      redirect_to new_shop_lookup_path, alert: "Google sign-in didn't finish. Start again from your shop's sign-in page."
    end
  end
end
