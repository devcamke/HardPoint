class MembershipsMailer < ApplicationMailer
  def invitation
    @membership = params[:membership]
    @account = @membership.account
    @user = @membership.user
    mail subject: "You've been added to #{@account.name} on HardPoint", to: @user.email_address
  end
end
