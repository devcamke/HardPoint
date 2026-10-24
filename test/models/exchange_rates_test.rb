require "test_helper"

class ExchangeRatesTest < ActiveSupport::TestCase
  setup do
    @acme, @bolt = accounts(:acme), accounts(:bolt)
    @usd = Current.set(account: @acme) { @acme.currencies.create!(code: "USD", rate: 129.5) }
    @eur = Current.set(account: @acme) { @acme.currencies.create!(code: "EUR", rate: 140, follows_market: false) }
    @bolt_usd = Current.set(account: @bolt) { @bolt.currencies.create!(code: "USD", rate: 130) }
    @feed = fake_transport(ExchangeRates, "/v6/latest/KES" => { result: "success", base_code: "KES", rates: { KES: 1, USD: 0.0077, EUR: 0.0072 } })
  end

  def refresh = ExchangeRates.refresh_all

  test "each morning every shop's currencies get the market rate; one request per home currency" do
    refresh
    Current.account = @acme
    assert_equal [ BigDecimal("129.87012987"), Date.current ], [ @usd.reload.market_rate, @usd.market_rate_on ]
    assert_equal BigDecimal("138.88888889"), @eur.reload.market_rate
    assert_equal BigDecimal("129.5"), @usd.rate, "not following: the shop's own rate stays"
    assert_equal 1, @feed.requests.size
    assert_equal "https://open.er-api.com/v6/latest/KES", @feed.requests.sole.url
    Current.account = @bolt
    assert_equal BigDecimal("129.87012987"), @bolt_usd.reload.market_rate
  end

  test "a followed currency moves to the market rate less the margin; a big jump waits for a manager" do
    Current.account = @acme
    @usd.update!(market_rate: 128, market_rate_on: Date.yesterday)
    @usd.update!(follows_market: true, margin_percent: 2)
    assert_equal BigDecimal("125.44"), @usd.rate, "turning it on takes the known market rate straight away"

    refresh
    Current.account = @acme
    assert_equal BigDecimal("127.27272727"), @usd.reload.rate, "129.87 less 2%"
    assert_nil @usd.updater

    @feed = fake_transport(ExchangeRates, "/v6/latest/KES" => { result: "success", rates: { USD: 0.0060 } }) # 166.67: a 31% jump
    refresh
    Current.account = @acme
    assert_equal [ BigDecimal("127.27272727"), BigDecimal("163.33333334") ], [ @usd.reload.rate, @usd.held_rate ]
    @usd.apply_market_rate
    assert_equal [ BigDecimal("163.33333334"), nil ], [ @usd.rate, @usd.held_rate ]
  end

  test "a feed that fails changes nothing, and following needs a market rate first" do
    fake_transport(ExchangeRates, "/v6/latest/KES" => [ 500, { result: "error", "error-type": "unsupported-code" } ])
    assert_nothing_raised { refresh }
    Current.account = @acme
    assert_nil @usd.reload.market_rate
    assert_not @usd.update(follows_market: true)
    assert_match "needs a market rate", @usd.errors.full_messages.to_sentence
  end
end
