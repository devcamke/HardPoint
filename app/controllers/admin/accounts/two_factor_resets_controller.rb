# HardPoint support turning off two-factor for someone who has lost their phone and recovery codes, usually a
# shop's only owner, after checking who they are. Recorded in the shop's activity with the administrator's email.
class Admin::Accounts::TwoFactorResetsController < Admin::BaseController
  include Admin::AccountScoped

  def create
    membership = @account.memberships.find(params[:membership_id])
    if membership.reset_two_factor(administrator: Current.administrator)
      back_to_account notice: "#{membership.user.name}'s two-factor sign-in is off; they've been signed out and emailed."
    else
      back_to_account alert: "#{membership.user.name} doesn't have two-factor sign-in on."
    end
  end
end
