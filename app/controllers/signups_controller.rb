class SignupsController < ApplicationController
  allow_unscoped_access
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_signup_path, alert: "Try again later." }

  layout "marketing"

  def new
    @signup = Signup.new(plan: Plan.all.map(&:key).include?(params[:plan]) ? params[:plan] : "business")
  end

  def create
    @signup = Signup.new(signup_params)

    if @signup.save
      redirect_to new_session_url(subdomain: @signup.account.subdomain, email_address: @signup.email_address),
        allow_other_host: true, notice: "Your shop is ready. Sign in to get started."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def signup_params
      params.expect(signup: %i[ shop_name subdomain owner_name email_address password plan ])
    end
end
