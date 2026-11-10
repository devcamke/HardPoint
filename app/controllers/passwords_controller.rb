class PasswordsController < ApplicationController
  allow_while_locked
  allow_unauthenticated_access
  allow_without_two_factor
  before_action :set_user_by_token, only: %i[ edit update ]
  # Per address, and per email address so nobody's inbox can be filled with reset emails from many addresses.
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }
  rate_limit to: 5, within: 15.minutes, only: :create, name: "email", by: -> { params[:email_address].to_s.strip.downcase },
    with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = Current.account.users.find_by(email_address: params[:email_address])
      PasswordsMailer.with(account: Current.account).reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      # The link came to their inbox, so the address is theirs.
      @user.confirm_email
      # Users are shared across shops, so sign them out of every shop (and the admin area), not only this one.
      @user.end_sessions
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    # A reset link (short-lived) or an invitation's set-password link (a few days).
    def set_user_by_token
      @user = Current.account.users.find_by_token_for(:invitation, params[:token].to_s) ||
        Current.account.users.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
