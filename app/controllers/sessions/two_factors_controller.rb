# Second step of signing in, for people with two-factor turned on.
class Sessions::TwoFactorsController < ApplicationController
  CHALLENGE_EXPIRES_IN = 10.minutes

  allow_unauthenticated_access
  allow_without_two_factor
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :set_challenged_user

  def new
  end

  def create
    if @user.verify_two_factor(params[:code])
      session.delete(:two_factor_challenge)
      start_new_session_for @user
      redirect_to after_authentication_url
    else
      redirect_to new_session_two_factor_path, alert: "That code didn't work. Try the latest code from your app, or a recovery code."
    end
  end

  private
    def set_challenged_user
      challenge = session[:two_factor_challenge] || {}

      if challenge["account_id"] == Current.account.id && challenge["started_at"].to_i > CHALLENGE_EXPIRES_IN.ago.to_i
        @user = Current.account.users.find_by(id: challenge["user_id"])
      end

      redirect_to new_session_path, alert: "Please sign in again." unless @user
    end
end
