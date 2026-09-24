# Each morning, yesterday's figures by email to owners, managers and accountants who want them.
module Account::DailySummary
  extend ActiveSupport::Concern

  SUMMARY_ROLES = %w[ owner manager accountant ].freeze

  class_methods do
    # Called by DailySummaryJob each morning, once for every shop, in the shop's time zone.
    def send_daily_summaries
      find_each do |account|
        Current.set(account: account) do
          Time.use_zone(account.time_zone) { account.send_daily_summary }
        end
      end
    end
  end

  def daily_summary_recipients
    users.where(memberships: { role: SUMMARY_ROLES, daily_summary: true }).pluck(:email_address)
  end

  # A day with no sales (closed, or not trading yet) sends nothing.
  def send_daily_summary(date = Time.zone.yesterday)
    if daily_summary_recipients.any? && sales.completed.where(completed_at: date.all_day).exists?
      ReportsMailer.with(account: self, date: date).daily_summary.deliver_later
    end
  end
end
