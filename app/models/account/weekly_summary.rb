# Each Monday morning, the week just gone (Monday to Sunday) by email to owners, managers and accountants who want it.
module Account::WeeklySummary
  extend ActiveSupport::Concern

  SUMMARY_ROLES = %w[ owner manager accountant ].freeze

  class_methods do
    # Called by WeeklySummaryJob on Monday mornings, once for every shop, in the shop's time zone.
    def send_weekly_summaries
      find_each do |account|
        Current.set(account: account) do
          Time.use_zone(account.time_zone) { account.send_weekly_summary }
        end
      end
    end
  end

  def weekly_summary_recipients
    users.where(memberships: { role: SUMMARY_ROLES, weekly_summary: true }).pluck(:email_address)
  end

  # A week without a sale (closed, or not trading yet) sends nothing.
  def send_weekly_summary(ends_on = Time.zone.today.beginning_of_week - 1)
    if weekly_summary_recipients.any? && sales.completed.where(completed_at: (ends_on - 6).beginning_of_day..ends_on.end_of_day).exists?
      ReportsMailer.with(account: self, ends_on: ends_on).weekly_summary.deliver_later
    end
  end
end
