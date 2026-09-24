# One event on its way to one endpoint. Signed so the receiver can check it came from HardPoint:
#
#   HardPoint-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<body>" with the endpoint's secret>
#
# Anything but a 2xx answer within 10 seconds is retried after 1 minute, 5, 30, then 2, 6 and 12 hours
# (a day in all), then marked failed. Receivers should use HardPoint-Delivery (the event id) to ignore repeats.
class WebhookDelivery < ApplicationRecord
  include AccountOwned

  RETRY_AFTER = [ 1.minute, 5.minutes, 30.minutes, 2.hours, 6.hours, 12.hours ].freeze
  RETENTION = 30.days

  class_attribute :transport, default: -> { Transport.new }.call

  belongs_to :endpoint, class_name: "WebhookEndpoint", inverse_of: :deliveries

  enum :status, %w[ pending delivered failed ].index_by(&:itself), default: "pending"

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :due, -> { pending.where(next_attempt_at: ..Time.current) }

  def deliver_later
    update_columns(next_attempt_at: Time.current)
    WebhookDeliveryJob.perform_later(self)
  end

  def deliver
    return unless pending? || failed?

    body = payload.to_json
    timestamp = Time.current.to_i
    response = transport.request(:post, endpoint.url, json: payload, headers: {
      "User-Agent" => "HardPoint-Webhooks/1", "HardPoint-Event" => event, "HardPoint-Delivery" => event_id,
      "HardPoint-Signature" => "t=#{timestamp},v1=#{self.class.signature(endpoint.secret, timestamp, body)}"
    })
    response.success? ? delivered(response) : attempt_failed("HTTP #{response.status}", response)
  rescue JsonHttp::Unreachable, Transport::Refused => error
    attempt_failed(error.message)
  end

  # Sent again as new (same event id, so receivers can still tell it's a repeat).
  def redeliver
    update!(status: :pending, attempts: 0, last_error: nil, next_attempt_at: Time.current)
    deliver_later
  end

  def self.signature(secret, timestamp, body)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  # Every minute: deliveries whose retry time has come, across shops.
  def self.retry_due
    Account.without_isolation { due.where("attempts > 0").includes(:account).to_a }.each do |delivery|
      Current.set(account: delivery.account) { delivery.deliver }
    end
  end

  def self.purge_old
    Account.without_isolation { where(created_at: ...RETENTION.ago).delete_all }
  end

  private
    def delivered(response)
      update!(status: :delivered, attempts: attempts + 1, response_status: response.status, response_body: excerpt(response),
        delivered_at: Time.current, next_attempt_at: nil, last_error: nil)
      endpoint.delivery_succeeded
    end

    def attempt_failed(reason, response = nil)
      retry_after = RETRY_AFTER[attempts]
      update!(attempts: attempts + 1, status: retry_after ? :pending : :failed, next_attempt_at: retry_after&.from_now,
        last_error: reason.to_s.first(250), response_status: response&.status, response_body: response && excerpt(response))
      endpoint.delivery_failed
    end

    def excerpt(response)
      body = response.body
      (body.is_a?(Hash) && body.key?("raw") ? body["raw"] : body.to_json).to_s.first(500)
    end
end
