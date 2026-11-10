# Preview all emails at http://localhost:3000/rails/mailers/memberships_mailer
class MembershipsMailerPreview < ActionMailer::Preview
  def invitation
    account = Account.first
    Current.account = account
    MembershipsMailer.with(membership: account.memberships.first).invitation
  end

  def added
    account = Account.first
    Current.account = account
    MembershipsMailer.with(membership: account.memberships.first).added
  end
end
