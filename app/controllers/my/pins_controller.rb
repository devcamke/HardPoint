class My::PinsController < ApplicationController
  allow_while_locked
  before_action :set_membership
  # Setting a PIN checks the password, so it can't be used to guess the password of a till left signed in.
  rate_limit to: 10, within: 3.minutes, only: :update, by: -> { cookies.signed[:session_id] || request.remote_ip },
    with: -> { redirect_to my_profile_path, alert: "Try again later." }

  def edit
  end

  def update
    if !Current.user.authenticate(params[:password])
      @membership.errors.add :base, "Your password wasn't right"
      render :edit, status: :unprocessable_entity
    elsif @membership.set_pin(params[:pin])
      redirect_to my_profile_path, notice: "Your till PIN is set."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @membership.remove_pin
    redirect_to my_profile_path, notice: "Your till PIN has been removed.", status: :see_other
  end

  private
    def set_membership
      @membership = Current.membership
      head :forbidden unless @membership.pin_role?
    end
end
