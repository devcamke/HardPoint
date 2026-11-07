# An owner turning off two-factor for a member of staff who has lost their phone and recovery codes. The owner
# confirms with their own password. Someone who also works for another shop is reset by HardPoint support.
class Memberships::TwoFactorResetsController < ApplicationController
  before_action :ensure_can_manage_account
  rate_limit to: 10, within: 3.minutes, with: -> { redirect_to memberships_path, alert: "Try again later." }

  before_action { redirect_to memberships_path, alert: "Not while HardPoint support is signed in as you." if Current.session.impersonated? }

  def create
    membership = Current.account.memberships.find(params[:membership_id])
    name = membership.user.name

    if membership.user == Current.user
      redirect_to edit_membership_path(membership), alert: "You can't reset your own two-factor here. Use a recovery code, or ask HardPoint support."
    elsif !membership.two_factor_resettable_by_shop?
      redirect_to edit_membership_path(membership), alert: "#{name} also uses HardPoint with another shop, so only HardPoint support can reset their two-factor."
    elsif !Current.user.authenticate(params[:password].to_s)
      redirect_to edit_membership_path(membership), alert: "Your password wasn't right, so nothing was changed."
    elsif membership.reset_two_factor
      redirect_to memberships_path, notice: "#{name}'s two-factor sign-in is off and they've been signed out. They've been emailed how to set it up again."
    else
      redirect_to edit_membership_path(membership), alert: "#{name} doesn't have two-factor sign-in on."
    end
  end
end
