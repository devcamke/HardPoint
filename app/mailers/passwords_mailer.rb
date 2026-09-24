class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @account = params[:account]
    mail subject: "Reset your #{@account.name} password", to: user.email_address
  end
end
