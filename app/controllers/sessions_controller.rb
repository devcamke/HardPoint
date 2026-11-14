class SessionsController < ApplicationController
  allow_while_locked
  allow_unauthenticated_access only: %i[ new create ]
  allow_without_two_factor
  # Per login from each address against password guessing, and a looser limit per address: every till in a shop
  # shares its router's public address, so a shift change can bring a dozen sign-ins at once. The login's limit
  # is per address too, so someone elsewhere typing an owner's email address can't lock the owner out of their shop.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "login", by: -> { "#{params[:email_address].to_s.strip.downcase} #{request.remote_ip}" },
    with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 60, within: 3.minutes, only: :create, name: "address", with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = Current.account.users.authenticate_by(params.permit(:email_address, :password))
      sign_in user, with: :password
    else
      redirect_to new_session_path(email_address: params[:email_address]), alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
