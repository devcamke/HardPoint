# Quick switch at a shared till: someone else steps up to an already signed-in till,
# picks their name and enters their PIN.
class Sessions::SwitchesController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to new_session_switch_path, alert: "Too many attempts. Wait a minute." }

  def new
    @memberships = Current.account.memberships.with_pin.alphabetically.includes(:user).excluding(Current.membership)
  end

  def create
    membership = Current.account.memberships.with_pin.find(params[:membership_id])

    if membership.switch_in_with_pin(params[:pin])
      terminate_session
      start_new_session_for membership.user, sign_in_method: :pin
      redirect_to root_path, notice: "Welcome, #{membership.user.name}."
    elsif membership.pin_locked?
      redirect_to new_session_switch_path, alert: "#{membership.user.name}'s PIN is locked after too many tries. Sign in with a password to set a new one."
    else
      redirect_to new_session_switch_path, alert: "That PIN wasn't right."
    end
  end
end
