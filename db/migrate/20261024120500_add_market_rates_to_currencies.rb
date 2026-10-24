class AddMarketRatesToCurrencies < ActiveRecord::Migration[8.1]
  def change
    # The day's market rate from the feed, kept whether or not the shop follows it.
    add_column :currencies, :market_rate, :decimal, precision: 18, scale: 8
    add_column :currencies, :market_rate_on, :date
    # Following the market: the rate is set each morning to the market rate less margin_percent,
    # unless it moved more than ExchangeRates::HOLD_PERCENT, which waits for a manager.
    add_column :currencies, :follows_market, :boolean, null: false, default: false
    add_column :currencies, :margin_percent, :decimal, precision: 5, scale: 2, null: false, default: 0
    add_column :currencies, :held_rate, :decimal, precision: 18, scale: 8
  end
end
