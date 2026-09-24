class My::ApprovalPinsController < ApplicationController
  allow_while_locked
  before_action :set_membership

  def edit
  end

  def update
    if !Current.user.authenticate(params[:password])
      @membership.errors.add :base, "Your password wasn't right"
      render :edit, status: :unprocessable_entity
    elsif @membership.set_approval_pin(params[:approval_pin])
      redirect_to my_profile_path, notice: "Your approval PIN is set."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_membership
      @membership = Current.membership
      head :forbidden unless @membership.approver?
    end
end
