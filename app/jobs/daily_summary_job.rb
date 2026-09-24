class DailySummaryJob < ApplicationJob
  queue_as :default

  def perform
    Account.send_daily_summaries
  end
end
