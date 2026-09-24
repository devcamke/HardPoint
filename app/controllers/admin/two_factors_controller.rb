class Admin::TwoFactorsController < Admin::BaseController
  CHALLENGE_EXPIRES_IN = 10.minutes

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_admin_session_path, alert: "Try again later." }
  before_action :set_challenged_user

  def new
    unless @user.two_factor_enabled?
      session[:pending_admin_two_factor_secret] ||= User.generate_two_factor_secret
      @secret = session[:pending_admin_two_factor_secret]
      @provisioning_uri = @user.two_factor_provisioning_uri(@secret)
    end
  end

  def create
    verified = if @user.two_factor_enabled?
      @user.verify_two_factor(params[:code])
    else
      @user.enable_two_factor(session.delete(:pending_admin_two_factor_secret), params[:code])
    end

    if verified
      session.delete(:admin_challenge)
      start_admin_session_for @user
      redirect_to admin_root_path
    else
      redirect_to new_admin_two_factor_path, alert: "That code didn't work."
    end
  end

  private
    def set_challenged_user
      challenge = session[:admin_challenge] || {}
      @user = User.find_by(id: challenge["user_id"], admin: true) if challenge["started_at"].to_i > CHALLENGE_EXPIRES_IN.ago.to_i
      redirect_to new_admin_session_path, alert: "Please sign in again." unless @user
    end
end
