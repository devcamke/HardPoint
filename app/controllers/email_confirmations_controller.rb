# The link in the sign-up email: opening it shows the address belongs to the person who signed up.
class EmailConfirmationsController < ApplicationController
  allow_unauthenticated_access
  allow_without_two_factor
  allow_while_locked
  rate_limit to: 10, within: 3.minutes, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def show
    if (user = User.find_by_token_for(:email_confirmation, params[:token]))
      user.confirm_email
      redirect_to new_session_path, notice: "Thanks, your email address is confirmed."
    else
      redirect_to new_session_path, alert: "That link has expired or was already used."
    end
  end
end
