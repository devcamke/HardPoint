class LowStockDigestJob < ApplicationJob
  one_at_a_time
  queue_as :default

  def perform
    Account.send_low_stock_digests
  end
end
