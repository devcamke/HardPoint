class LowStockDigestJob < ApplicationJob
  queue_as :default

  def perform
    Account.send_low_stock_digests
  end
end
