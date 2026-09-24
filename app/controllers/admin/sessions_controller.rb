class Admin::SessionsController < Admin::BaseController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_admin_session_path, alert: "Try again later." }

  def new
  end

  # Password first; every administrator then has to pass (or set up) two-factor.
  def create
    user = User.authenticate_by(params.permit(:email_address, :password))

    if user&.admin?
      session[:admin_challenge] = { "user_id" => user.id, "started_at" => Time.current.to_i }
      redirect_to new_admin_two_factor_path
    else
      redirect_to new_admin_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_admin_session
    redirect_to new_admin_session_path, status: :see_other
  end
end
