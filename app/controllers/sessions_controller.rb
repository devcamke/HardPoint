class SessionsController < ApplicationController
  allow_while_locked
  allow_unauthenticated_access only: %i[ new create ]
  allow_without_two_factor
  # Per login against password guessing, and a looser limit per address: every till in a shop shares
  # its router's public address, so a shift change can bring a dozen sign-ins at once.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "login", by: -> { params[:email_address].to_s.strip.downcase },
    with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 60, within: 3.minutes, only: :create, name: "address", with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = Current.account.users.authenticate_by(params.permit(:email_address, :password))
      if Current.account.closing? && !Current.account.memberships.find_by(user: user)&.owner?
        redirect_to new_session_path, alert: "#{Current.account.name} is closing; only its owners can sign in."
      elsif user.two_factor_enabled?
        session[:two_factor_challenge] = { "user_id" => user.id, "account_id" => Current.account.id, "started_at" => Time.current.to_i }
        redirect_to new_session_two_factor_path
      else
        start_new_session_for user
        redirect_to after_authentication_url
      end
    else
      redirect_to new_session_path(email_address: params[:email_address]), alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
