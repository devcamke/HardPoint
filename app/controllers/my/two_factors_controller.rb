class My::TwoFactorsController < ApplicationController
  allow_while_locked
  allow_without_two_factor
  rate_limit to: 10, within: 3.minutes, only: %i[ create destroy ], by: -> { "user-#{Current.user&.id}" },
    with: -> { redirect_to my_profile_path, alert: "Try again later." }
  # Support signed in as someone mustn't enrol their own phone as that person's second factor, or switch it off.
  refuse_while_impersonated back_to: -> { my_profile_path }, only: %i[ new create destroy ]
  before_action :ensure_not_enabled, only: %i[ new create ]

  def new
    session[:pending_two_factor_secret] ||= User.generate_two_factor_secret
    @secret = session[:pending_two_factor_secret]
    @provisioning_uri = Current.user.two_factor_provisioning_uri(@secret)
  end

  def create
    if recovery_codes = Current.user.enable_two_factor(session[:pending_two_factor_secret], params[:code])
      session.delete(:pending_two_factor_secret)
      session[:new_recovery_codes] = recovery_codes
      redirect_to my_recovery_codes_path
    else
      redirect_to new_my_two_factor_path, alert: "That code didn't match. Check your phone's time is set automatically and try the newest code."
    end
  end

  # Needs the password and a code: a till left signed in, or a password someone learned, isn't enough to turn it off.
  def destroy
    if !Current.user.authenticate(params[:password].to_s)
      redirect_to my_profile_path, alert: "That password wasn't right, so two-factor sign-in is still on."
    elsif !Current.user.verify_two_factor(params[:code])
      redirect_to my_profile_path, alert: "That code didn't work, so two-factor sign-in is still on. Use the latest code from your app, or a recovery code."
    else
      Current.user.disable_two_factor
      redirect_to my_profile_path, notice: "Two-factor sign-in is off."
    end
  end

  private
    def ensure_not_enabled
      redirect_to my_profile_path, notice: "Two-factor sign-in is already on." if Current.user.two_factor_enabled?
    end
end
