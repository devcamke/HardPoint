# Where a shop wants to hear about changes: a URL, the events it cares about, and a signing secret.
# After too many failed attempts in a row it switches itself off and the owners are emailed.
class WebhookEndpoint < ApplicationRecord
  include AccountOwned, Eventable

  EVENTS = {
    "sale.completed" => "A sale is completed at a till (or arrives from an offline till)",
    "sale.voided" => "A sale is voided",
    "product.created" => "A product is added",
    "product.updated" => "A product's details or price change",
    "stock.changed" => "Stock of a product changes at a branch",
    "order.created" => "A quote or order is made",
    "order.updated" => "An order is confirmed, ready, collected or cancelled",
    "customer.created" => "A customer is added",
    "customer.updated" => "A customer's details change"
  }.freeze
  MAX_CONSECUTIVE_FAILURES = 25

  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :deliveries, class_name: "WebhookDelivery", foreign_key: :endpoint_id, dependent: :delete_all, inverse_of: :endpoint

  encrypts :secret

  validates :url, presence: true, length: { maximum: 500 }
  validates :description, length: { maximum: 100 }
  validate :url_is_public_https
  validate { errors.add :event_types, "choose at least one" if event_types.blank? }
  validate { errors.add :event_types, "include unknown ones: #{(event_types - EVENTS.keys).join(", ")}" if (Array(event_types) - EVENTS.keys).any? }
  validate(on: :create) { errors.add :base, "Webhooks are on the Business and Enterprise plans" unless account&.subscription_plan&.api? }

  before_validation(on: :create) { self.secret ||= generate_secret }
  before_validation { self.event_types = Array(event_types).compact_blank.uniq }
  after_create { track_event "created", url: url }

  scope :enabled, -> { where(active: true, disabled_at: nil) }
  scope :subscribed_to, ->(event) { where("webhook_endpoints.event_types ? :event", event: event) }
  scope :alphabetically, -> { order(:url) }

  # Queues the event for every endpoint that wants it. `record` is rendered with the API's own JSON.
  def self.publish(account, event, record)
    Current.set(account: account) do
      endpoints = account.webhook_endpoints.enabled.subscribed_to(event).to_a
      return if endpoints.empty?

      payload = { id: SecureRandom.uuid, type: event, created_at: Time.current.utc.iso8601, shop: account.subdomain, data: WebhookPayload.for(record) }
      endpoints.each { |endpoint| endpoint.deliveries.create!(account: account, event: event, event_id: payload[:id], payload: payload).deliver_later }
    end
  end

  def name = url

  def enabled?
    active? && disabled_at.nil?
  end

  def send_test
    payload = { id: SecureRandom.uuid, type: "ping", created_at: Time.current.utc.iso8601, shop: account.subdomain, data: { message: "Hello from HardPoint" } }
    deliveries.create!(account: account, event: "ping", event_id: payload[:id], payload: payload).tap(&:deliver_later)
  end

  def roll_secret
    update!(secret: generate_secret)
    track_event "secret_rolled"
  end

  def enable
    update!(active: true, disabled_at: nil, disabled_reason: nil, failure_count: 0)
  end

  def delivery_succeeded
    update_columns(failure_count: 0) if failure_count.positive?
  end

  def delivery_failed
    increment!(:failure_count)
    return unless failure_count >= MAX_CONSECUTIVE_FAILURES && disabled_at.nil?

    update!(disabled_at: Time.current, disabled_reason: "#{failure_count} deliveries in a row failed")
    track_event "disabled", creator: nil, url: url
    WebhooksMailer.with(endpoint: self).disabled.deliver_later
  end

  private
    def generate_secret
      "whsec_#{SecureRandom.base58(32)}"
    end

    def url_is_public_https
      uri = URI.parse(url.to_s)
      if !uri.is_a?(URI::HTTPS) && !(uri.is_a?(URI::HTTP) && WebhookDelivery::Transport.private_addresses_allowed?)
        errors.add :url, "must start with https://"
      elsif uri.host.blank? || (!WebhookDelivery::Transport.private_addresses_allowed? && WebhookDelivery::Transport.private_host?(uri.host))
        errors.add :url, "must be a public internet address"
      end
    rescue URI::InvalidURIError
      errors.add :url, "isn't a valid address"
    end
end
