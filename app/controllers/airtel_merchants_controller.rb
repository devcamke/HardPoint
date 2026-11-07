# Settings › Airtel Money: the shop's merchant accounts on Airtel Africa's Open API.
class AirtelMerchantsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_merchant, only: %i[ edit update ]

  def index
    @merchants = Current.account.airtel_merchants.includes(:branch).order(:name)
  end

  def new
    @merchant = Current.account.airtel_merchants.new(environment: Mpesa::Shortcode.simulator_allowed? ? "sandbox" : "production")
  end

  def create
    @merchant = Current.account.airtel_merchants.new(merchant_params)

    if @merchant.save
      redirect_to airtel_merchants_path, notice: "#{@merchant.name} added. Test the connection, then give Airtel the callback address shown."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Blank secret fields keep the saved secrets; they're never shown again once saved.
  def update
    if @merchant.update(merchant_params.compact_blank.merge(merchant_params.slice(:branch_id, :merchant_number, :active)))
      redirect_to airtel_merchants_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_merchant
      @merchant = Current.account.airtel_merchants.find(params[:id])
    end

    def merchant_params
      permitted = params.expect(airtel_merchant: %i[ name branch_id environment merchant_number client_id client_secret active ])
      permitted[:branch_id] = Current.account.branches.find(permitted[:branch_id]).id if permitted[:branch_id].present?
      permitted
    end
end
