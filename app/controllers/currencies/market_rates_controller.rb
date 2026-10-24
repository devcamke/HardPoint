# Takes the market rate (less the margin), or a rate held back for being a big jump, as the currency's rate.
class Currencies::MarketRatesController < ApplicationController
  before_action { head :forbidden unless current_membership&.approver? }

  def create
    currency = Current.account.currencies.find(params[:currency_id])
    if currency.market_rate && currency.apply_market_rate
      redirect_to currencies_path, notice: "#{currency.code} is now #{helpers.plain_number(currency.rate.round(4))} #{Current.account.currency}."
    else
      redirect_to currencies_path, alert: "There's no market rate for #{currency.code} yet."
    end
  end
end
