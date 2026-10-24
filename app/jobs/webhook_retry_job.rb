# Every minute: webhook deliveries whose retry time has come.
class WebhookRetryJob < ApplicationJob
  one_at_a_time(duration: 15.minutes)

  def perform
    WebhookDelivery.retry_due
  end
end
