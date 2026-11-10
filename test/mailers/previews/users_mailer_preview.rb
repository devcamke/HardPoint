# Preview all emails at http://localhost:3000/rails/mailers/users_mailer
class UsersMailerPreview < ActionMailer::Preview
  def two_factor_locked
    UsersMailer.with(user: User.first).two_factor_locked
  end
end
