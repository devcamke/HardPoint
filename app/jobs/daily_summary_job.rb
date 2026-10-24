class DailySummaryJob < ApplicationJob
  one_at_a_time
  queue_as :default

  def perform
    Account.send_daily_summaries
  end
end
