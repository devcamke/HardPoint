# Where texts go in development and tests: kept in memory (and the log) instead of sent, like
# Action Mailer's test deliveries.
module Sms::Outbox
  mattr_accessor :deliveries, default: []

  def self.request(_method, _url, form:, **)
    deliveries << form
    Rails.logger.info "[SMS] to #{form[:to]}: #{form[:message]}"
    JsonHttp::Response.new(201, { "SMSMessageData" => { "Message" => "Sent to 1/1", "Recipients" => [
      { "statusCode" => 101, "number" => form[:to], "status" => "Success", "cost" => "KES 0.8000", "messageId" => "ATXid_#{SecureRandom.hex(8)}" } ] } })
  end
end
