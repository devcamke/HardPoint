# Each morning's market exchange rates, for every shop that takes or buys in another currency.
class ExchangeRatesJob < ApplicationJob
  one_at_a_time
  retry_on JsonHttp::Unreachable, wait: 30.minutes, attempts: 4

  def perform
    ExchangeRates.refresh_all
  end
end
