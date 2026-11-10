# Sends one WhatsApp message. Meta being unreachable is retried; a refusal is recorded on the message.
class Whatsapp::DeliveryJob < ApplicationJob
  queue_as :default
  retry_on JsonHttp::Unreachable, wait: :polynomially_longer, attempts: 5

  def perform(message)
    message.send_now
  end
end
