# Every minute: webhook deliveries whose retry time has come.
class WebhookRetryJob < ApplicationJob
  def perform
    WebhookDelivery.retry_due
  end
end
