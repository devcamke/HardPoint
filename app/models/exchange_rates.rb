# The day's market exchange rates, from a public feed (open.er-api.com by default; another feed with
# the same shape can be set as exchange_rates_url in the platform's credentials, with %{base} for
# the shop's currency). One request per home currency, however many shops use it.
class ExchangeRates
  DEFAULT_URL = "https://open.er-api.com/v6/latest/%{base}"
  # A move bigger than this from the shop's current rate isn't applied by itself: a bad feed
  # shouldn't change what the till takes for a dollar without someone looking.
  HOLD_PERCENT = 10

  Unavailable = Class.new(StandardError)

  class_attribute :transport, default: JsonHttp.new

  # Every shop with a currency, its market rates refreshed; followed currencies updated.
  def self.refresh_all
    feed = new
    Account.where(id: Account.without_isolation { Currency.distinct.pluck(:account_id) }).find_each do |account|
      Current.set(account: account) { feed.refresh(account) }
    rescue Unavailable, JsonHttp::Unreachable => error
      Rails.logger.warn "Exchange rates for #{account.subdomain}: #{error.message}"
    end
  end

  def initialize
    @quotes = {}
  end

  # { "USD" => 129.4 } in the base currency: what one unit of each currency is worth.
  def quotes(base)
    @quotes[base] ||= begin
      response = transport.request(:get, format(url, base: base))
      rates = response.body["rates"]
      raise Unavailable, "The rates feed said #{response.body["result"] || response.status}" unless response.success? && rates.is_a?(Hash)

      rates.except(base).filter_map { |code, per_base| [ code, (1 / per_base.to_d).round(8) ] if per_base.to_d.positive? }.to_h
    end
  end

  def refresh(account, on: Time.current.in_time_zone(account.time_zone).to_date)
    quotes = quotes(account.currency)
    account.currencies.each do |currency|
      next unless (market = quotes[currency.code])
      currency.take_market_rate(market, on: on)
    end
  end

  private
    def url
      Rails.application.credentials.exchange_rates_url || DEFAULT_URL
    end
end
