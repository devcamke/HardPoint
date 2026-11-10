class My::ApprovalPinsController < ApplicationController
  allow_while_locked
  before_action :set_membership
  # Setting a PIN checks the password, so it can't be used to guess the password of a till left signed in; and a
  # refused PIN means a colleague has it. Tries are counted per person, so signing in again doesn't start afresh.
  rate_limit to: 10, within: 3.minutes, only: :update, by: -> { "membership-#{Current.membership&.id}" },
    with: -> { redirect_to my_profile_path, alert: "Try again later." }

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
