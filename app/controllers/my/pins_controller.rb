class My::PinsController < ApplicationController
  before_action :set_membership

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
