class MembershipsMailer < ApplicationMailer
  def invitation
    @membership = params[:membership]
    @account = @membership.account
    @user = @membership.user
    mail subject: "You've been added to #{@account.name} on HardPoint", to: @user.email_address
  end

  # For someone who already has a HardPoint sign-in (from another shop): no password to choose.
  def added
    @membership = params[:membership]
    @account = @membership.account
    @user = @membership.user
    mail subject: "You've been added to #{@account.name} on HardPoint", to: @user.email_address
  end

  def two_factor_reset
    @membership = params[:membership]
    @account = @membership.account
    @user = @membership.user
    @by = params[:by]
    mail subject: "Your two-factor sign-in for #{@account.name} was reset", to: @user.email_address
  end
end
