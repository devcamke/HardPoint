class UsersMailer < ApplicationMailer
  # Sent at sign-up, so the person who opened the shop shows the address is theirs.
  def email_confirmation(user)
    @user = user
    @account = params[:account]
    mail subject: "Confirm your email address for HardPoint", to: user.email_address
  end
end
