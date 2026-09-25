# The other currencies a shop takes or buys in, and today's rates. Owners and managers keep the
# rates up to date; every change is in the activity log, and past payments keep their own rate.
class CurrenciesController < ApplicationController
  before_action :ensure_approver, except: :index
  before_action :set_currency, only: %i[ update destroy ]

  def index
    @currencies = Current.account.currencies.alphabetically.includes(:updater)
    @currency = Current.account.currencies.new
  end

  def create
    @currency = Current.account.currencies.new(currency_params)
    if @currency.save
      redirect_to currencies_path, notice: "#{@currency.name} added."
    else
      @currencies = Current.account.currencies.alphabetically.includes(:updater)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @currency.update(currency_params)
      redirect_to currencies_path, notice: "#{@currency.code} rate saved."
    else
      redirect_to currencies_path, alert: @currency.errors.full_messages.to_sentence
    end
  end

  # Payments and orders keep their own code and rate, so a currency can go without losing history.
  def destroy
    @currency.destroy
    redirect_to currencies_path, notice: "#{@currency.code} removed."
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end

    def set_currency
      @currency = Current.account.currencies.find(params[:id])
    end

    def currency_params
      params.expect(currency: %i[ code rate accepted_at_till ]).tap { _1.delete(:code) if @currency&.persisted? }
    end
end
