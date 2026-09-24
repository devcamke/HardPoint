# Preview at http://demo.localhost:3000/rails/mailers/reports_mailer/daily_summary
class ReportsMailerPreview < ActionMailer::Preview
  def daily_summary
    account = Account.first
    Current.account = account
    ReportsMailer.with(account: account, date: Time.zone.today).daily_summary
  end
end
