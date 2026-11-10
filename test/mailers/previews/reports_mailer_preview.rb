# Preview at http://demo.localhost:3000/rails/mailers/reports_mailer
class ReportsMailerPreview < ActionMailer::Preview
  def daily_summary
    account = Account.first
    Current.account = account
    ReportsMailer.with(account: account, date: Time.use_zone(account.time_zone) { Time.zone.yesterday }).daily_summary
  end

  def weekly_summary
    account = Account.first
    Current.account = account
    ReportsMailer.with(account: account, ends_on: Time.use_zone(account.time_zone) { Time.zone.today.beginning_of_week - 1 }).weekly_summary
  end
end
