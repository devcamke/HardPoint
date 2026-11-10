class Admin::TwoFactorsController < Admin::BaseController
  CHALLENGE_EXPIRES_IN = 10.minutes

  allow_unauthenticated_access
  # Per address, and per administrator being challenged. Wrong codes also count towards the person's lockout.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "address", with: -> { redirect_to new_admin_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 3.minutes, only: :create, name: "administrator", by: -> { "admin-#{session.dig(:admin_challenge, "user_id")}" },
    with: -> { redirect_to new_admin_session_path, alert: "Try again later." }
  before_action :set_challenged_user

  def new
    if !@user.two_factor_enabled? && may_enrol?
      session[:pending_admin_two_factor_secret] ||= User.generate_two_factor_secret
      @secret = session[:pending_admin_two_factor_secret]
      @provisioning_uri = @user.two_factor_provisioning_uri(@secret)
    end
  end

  def create
    verified = if @user.two_factor_enabled?
      @user.verify_two_factor(params[:code])
    elsif may_enrol?
      @user.enable_two_factor(session.delete(:pending_admin_two_factor_secret), params[:code])
    end

    if verified
      session.delete(:admin_challenge)
      session.delete(:admin_enrolment_token)
      start_admin_session_for @user
      AdminEvent.record "signed_in", user: @user, ip_address: request.remote_ip
      redirect_to admin_root_path
    elsif @user.two_factor_locked?
      redirect_to new_admin_two_factor_path, alert: "Too many wrong codes. Wait #{User::TwoFactor::LOCKOUT.in_minutes.to_i} minutes, then try again."
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

    # Setting two-factor up needs an enrolment link made for this administrator on the server, not only their password.
    def may_enrol?
      User.find_by_token_for(:admin_enrolment, session[:admin_enrolment_token].to_s) == @user
    end
    helper_method :may_enrol?
end
