# Emails about a person's own HardPoint sign-in, which is shared by every shop they work for.
class UsersMailer < ApplicationMailer
  # Sent at sign-up, so the person who opened the shop shows the address is theirs.
  def email_confirmation(user)
    @user = user
    @account = params[:account]
    mail subject: "Confirm your email address for HardPoint", to: user.email_address
  end

  # Someone typed this person's password and then too many wrong two-factor codes.
  def two_factor_locked
    @user = params[:user]
    @minutes = User::TwoFactor::LOCKOUT.in_minutes.to_i
    mail subject: "Too many wrong two-factor codes on your HardPoint sign-in", to: @user.email_address
  end
end
