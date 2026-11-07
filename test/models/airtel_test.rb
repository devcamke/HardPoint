require "test_helper"

class AirtelTest < ActiveSupport::TestCase
  include FakeTransportHelper

  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @merchant = accounts(:acme).airtel_merchants.create!(name: "Airtel", environment: "sandbox", client_id: "id-123", client_secret: "secret-456")
    @sale = shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails), quantity: 4) }
  end

  test "a prompt goes to Airtel with the number without 254, whole shillings and our own transaction ID" do
    fake = fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
      Airtel::Client::PAYMENT_PATH => { status: { success: true, code: "200" } })

    request = @merchant.request_payment(sale: @sale, phone: "0733 123 456", amount_cents: 1000_50)
    assert request.pending?

    token = fake.last(Airtel::Client::TOKEN_PATH)
    assert_equal({ "client_id" => "id-123", "client_secret" => "secret-456", "grant_type" => "client_credentials" }, token.json.deep_stringify_keys)
    payment = fake.last(Airtel::Client::PAYMENT_PATH)
    assert_equal [ "Bearer token-1", "KE", "KES" ], payment.headers.values_at("Authorization", "X-Country", "X-Currency")
    assert_equal({ country: "KE", currency: "KES", msisdn: "733123456" }, payment.json[:subscriber])
    assert_equal({ amount: 1001, country: "KE", currency: "KES", id: request.transaction_id }, payment.json[:transaction])
    assert_match "openapiuat.airtel.africa", payment.url
  end

  test "a refused prompt fails with Airtel's message" do
    fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
      Airtel::Client::PAYMENT_PATH => [ 400, { status: { success: false, message: "Invalid MSISDN" } } ])

    request = @merchant.request_payment(sale: @sale, phone: "0733 123 456", amount_cents: 1000_00)
    assert request.failed?
    assert_equal "Invalid MSISDN", request.result_description
  end

  test "a late callback is chased by asking Airtel, and the sale is paid with the Airtel receipt" do
    fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
      Airtel::Client::PAYMENT_PATH => { status: { success: true } })
    request = @merchant.request_payment(sale: @sale, phone: "0733 123 456", amount_cents: @sale.balance_due_cents)

    travel 30.seconds do
      fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
        "/standard/v1/payments/#{request.transaction_id}" => { data: { transaction: { id: request.transaction_id, status: "TS", airtel_money_id: "MP2611.0001.A1B2C" } } })
      request.check_status
    end

    assert request.reload.paid?
    payment = @sale.reload.payments.sole
    assert_equal [ "airtel_money", "MP2611.0001.A1B2C", "Airtel Money" ], [ payment.tender, payment.reference, payment.label ]
    assert @sale.completed?
    assert_equal "06", Etims::PAYMENT_TYPES.fetch(payment.tender)
  end

  test "callbacks are safe twice, and a payment that arrives after the till gave up can be used later" do
    fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
      Airtel::Client::PAYMENT_PATH => { status: { success: true } })
    request = @merchant.request_payment(sale: @sale, phone: "0733 123 456", amount_cents: @sale.balance_due_cents)
    request.cancel

    payload = { "transaction" => { "id" => request.transaction_id, "status_code" => "TS", "airtel_money_id" => "MP2611.0002.X" } }
    2.times { @merchant.receive_callback(payload) }
    assert request.reload.paid?, "the money arrived, so it's kept"
    assert_empty @sale.reload.payments, "but not put on the sale the till gave up on"
    assert_equal [ request ], Airtel::Request.unused.to_a

    request.update!(status: "pending")
    2.times { @merchant.receive_callback(payload) }
    assert_equal 1, @sale.reload.payments.count
  end

  test "an unused payment goes on another sale, once" do
    request = @merchant.requests.create!(account: accounts(:acme), sale: @sale, phone: "254733123456", amount_cents: 300_00,
      status: "paid", airtel_money_id: "MP2611.0003.Y", resolved_at: Time.current)
    other = shifts(:acme_front_open).current_sale

    payment = request.use_on(other)
    assert_equal [ "airtel_money", 300_00 ], [ payment.tender, payment.amount_cents ]
    assert_nil request.use_on(other), "used once only"
    assert_empty Airtel::Request.unused
  end

  test "failures and no answer" do
    request = @merchant.requests.create!(account: accounts(:acme), sale: @sale, phone: "254733123456", amount_cents: 100_00)
    request.resolve(status_code: "TF", message: "Insufficient funds")
    assert_equal [ "failed", "Insufficient funds" ], [ request.status, request.result_description ]

    waiting = @merchant.requests.create!(account: accounts(:acme), sale: @sale, phone: "254733123456", amount_cents: 100_00)
    travel 4.minutes do
      fake_transport(Airtel::Client, Airtel::Client::TOKEN_PATH => { access_token: "token-1" },
        "/standard/v1/payments/#{waiting.transaction_id}" => { data: { transaction: { status: "TIP" } } })
      waiting.check_status
    end
    assert waiting.reload.expired?
  end

  test "credentials are needed except on the simulator, which isn't allowed on a live server" do
    assert_not accounts(:acme).airtel_merchants.new(name: "Airtel", environment: "production").valid?
    assert accounts(:acme).airtel_merchants.new(name: "Airtel", environment: "simulator").valid?
  end
end
