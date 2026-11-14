# "Sign in with Google" on a shop's sign-in page: sends the person to Google, and signs them in when they come
# back with an address Google vouches for that is on this shop's staff (GoogleSignIn has the whole route).
class Sessions::GooglesController < ApplicationController
  allow_while_locked
  allow_unauthenticated_access
  allow_without_two_factor
  rate_limit to: 20, within: 3.minutes, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :require_google_sign_in

  def new
    started = GoogleSignIn.start(account: Current.account, redirect_uri: google_callback_url(subdomain: false))
    session[:google_sign_in_nonce] = started.nonce
    redirect_to started.url, allow_other_host: true
  end

  def show
    email = GoogleSignIn.email_for(params[:token], account: Current.account, nonce: session.delete(:google_sign_in_nonce))

    if email.nil?
      redirect_to new_session_path, alert: "Google sign-in didn't finish. Try again, or use your password."
    elsif user = Current.account.users.find_by(email_address: email)
      sign_in user, with: :google
    else
      redirect_to new_session_path, alert: "Nobody at #{Current.account.name} signs in as #{email}. Ask an owner to add you with that address."
    end
  end

  private
    def require_google_sign_in
      redirect_to new_session_path unless GoogleSignIn.configured?
    end
end
