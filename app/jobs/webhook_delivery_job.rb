class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks
  discard_on ActiveJob::DeserializationError

  def perform(delivery)
    delivery.deliver if delivery.pending? && delivery.attempts.zero?
  end
end
