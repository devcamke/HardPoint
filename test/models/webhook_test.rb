require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
    @endpoint = @account.webhook_endpoints.create!(url: "https://hooks.example.com/hardpoint", event_types: %w[ sale.completed stock.changed product.updated ])
  end

  def sell_nails
    shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails), quantity: 2); _1.pay(tender: "cash") }
  end

  test "a completed sale is sent, signed, with the API's own JSON" do
    receiver = fake_transport(WebhookDelivery, "/hardpoint" => {})
    sale = nil
    perform_enqueued_jobs(only: WebhookDeliveryJob) { sale = sell_nails }

    sent = receiver.requests.find { _1.headers["HardPoint-Event"] == "sale.completed" }
    assert sent, "sale.completed was sent"
    assert_equal sale.id, sent.json.dig("data", "id")
    assert_equal "completed", sent.json.dig("data", "status")
    assert_equal "acme", sent.json["shop"]

    timestamp, signature = sent.headers["HardPoint-Signature"].scan(/t=(\d+),v1=(\h+)/).first
    assert_equal WebhookDelivery.signature(@endpoint.secret, timestamp, sent.json.to_json), signature
    assert receiver.requests.any? { _1.headers["HardPoint-Event"] == "stock.changed" }, "stock changes are sent too"
    assert @account.webhook_deliveries.where(event: "sale.completed").sole.delivered?
  end

  test "only subscribed events are sent" do
    assert_no_difference -> { WebhookDelivery.count } do
      @account.customers.create!(name: "Not subscribed")
    end
    assert_difference -> { WebhookDelivery.count } do
      products(:acme_nails).update!(price_cents: 26000)
    end
  end

  test "failures are retried with back-off, then the delivery fails" do
    fake_transport(WebhookDelivery, "/hardpoint" => [ 500, {} ])
    delivery = @endpoint.send_test
    delivery.deliver

    assert delivery.reload.pending?
    assert_equal [ 1, 500 ], [ delivery.attempts, delivery.response_status ]
    assert_in_delta 1.minute.from_now, delivery.next_attempt_at, 5.seconds

    travel 2.minutes do
      WebhookDelivery.retry_due
      assert_equal 2, delivery.reload.attempts
    end

    delivery.update!(attempts: WebhookDelivery::RETRY_AFTER.size)
    delivery.deliver
    assert delivery.reload.failed?
  end

  test "an unreachable receiver counts as a failure" do
    fake_transport(WebhookDelivery, "/hardpoint" => JsonHttp::Unreachable.new("hooks.example.com: connection refused"))
    delivery = @endpoint.send_test
    delivery.deliver
    assert_match "connection refused", delivery.reload.last_error
  end

  test "an endpoint that keeps failing is switched off and the owners told" do
    fake_transport(WebhookDelivery, "/hardpoint" => [ 404, {} ])
    @endpoint.update!(failure_count: WebhookEndpoint::MAX_CONSECUTIVE_FAILURES - 1)

    assert_enqueued_email_with WebhooksMailer, :disabled, params: { endpoint: @endpoint } do
      @endpoint.send_test.deliver
    end
    assert_not @endpoint.reload.enabled?

    assert_no_difference -> { WebhookDelivery.count } do
      products(:acme_nails).update!(price_cents: 27000)
    end
    @endpoint.enable
    assert @endpoint.enabled?
  end

  test "webhooks only go to public HTTPS addresses" do
    Rails.configuration.x.webhooks_allow_private_addresses = false
    %w[ http://hooks.example.com/x https://localhost/x https://127.0.0.1/x https://10.1.2.3/x https://169.254.169.254/latest https://[::1]/x ].each do |url|
      endpoint = WebhookEndpoint.new(account: @account, url: url, event_types: %w[ sale.completed ])
      assert_not endpoint.valid?, "#{url} should be refused"
    end
    assert WebhookEndpoint.new(account: @account, url: "https://hooks.example.com/x", event_types: %w[ sale.completed ]).valid?

    # A name that resolves to a private address is refused when sending, too.
    error = assert_raises(WebhookDelivery::Transport::Refused) { WebhookDelivery::Transport.new.request(:post, "https://localhost/x", json: {}) }
    assert_match "private address", error.message
  ensure
    Rails.configuration.x.webhooks_allow_private_addresses = true
  end

  test "events must be known ones, and webhooks need the API plan" do
    assert_not WebhookEndpoint.new(account: @account, url: "https://hooks.example.com/y", event_types: %w[ sale.eaten ]).valid?

    @account.update!(plan: "starter")
    endpoint = @account.webhook_endpoints.create(url: "https://hooks.example.com/z", event_types: %w[ sale.completed ])
    assert_match "Business and Enterprise", endpoint.errors.full_messages.to_sentence
  end

  test "the secret is encrypted and can be rolled" do
    old = @endpoint.secret
    assert_not_includes WebhookEndpoint.connection.select_value("SELECT secret FROM webhook_endpoints WHERE id = #{@endpoint.id}"), old
    @endpoint.roll_secret
    assert_not_equal old, @endpoint.reload.secret
    assert @endpoint.secret.start_with?("whsec_")
  end
end
