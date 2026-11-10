class Admin::SessionsController < Admin::BaseController
  allow_unauthenticated_access only: %i[ new create ]
  # Per address, and per login so guessing one administrator's password from many addresses is slow too.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "address", with: -> { redirect_to new_admin_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 3.minutes, only: :create, name: "login", by: -> { params[:email_address].to_s.strip.downcase },
    with: -> { redirect_to new_admin_session_path, alert: "Try again later." }

  # An enrolment link (bin/rails admin:enrolment_link[email]) lands here; it's kept for the two-factor step.
  def new
    session[:admin_enrolment_token] = params[:enrolment_token] if params[:enrolment_token].present?
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
