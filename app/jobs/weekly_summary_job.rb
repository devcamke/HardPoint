class WeeklySummaryJob < ApplicationJob
  one_at_a_time
  queue_as :default

  def perform
    Account.send_weekly_summaries
  end
end
