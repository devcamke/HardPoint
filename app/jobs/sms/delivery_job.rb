class Sms::DeliveryJob < ApplicationJob
  retry_on JsonHttp::Unreachable, wait: :polynomially_longer, attempts: 5

  def perform(message)
    message.deliver
  end
end
