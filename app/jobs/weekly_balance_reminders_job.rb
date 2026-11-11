class WeeklyBalanceRemindersJob < ApplicationJob
  one_at_a_time
  queue_as :default

  def perform
    Account.send_weekly_balance_reminders
  end
end
