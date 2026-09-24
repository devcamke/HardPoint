class My::TwoFactorsController < ApplicationController
  allow_while_locked
  allow_without_two_factor
  rate_limit to: 10, within: 3.minutes, only: %i[ create destroy ], with: -> { redirect_to my_profile_path, alert: "Try again later." }
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

  def destroy
    if Current.user.authenticate(params[:password])
      Current.user.disable_two_factor
      redirect_to my_profile_path, notice: "Two-factor sign-in is off."
    else
      redirect_to my_profile_path, alert: "That password wasn't right, so two-factor sign-in is still on."
    end
  end

  private
    def ensure_not_enabled
      redirect_to my_profile_path, notice: "Two-factor sign-in is already on." if Current.user.two_factor_enabled?
    end
end
