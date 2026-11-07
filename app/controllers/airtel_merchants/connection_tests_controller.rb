class AirtelMerchants::ConnectionTestsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    merchant = Current.account.airtel_merchants.find(params[:airtel_merchant_id])
    merchant.test_connection
    redirect_to airtel_merchants_path, notice: "Connected to Airtel with #{merchant.name}'s credentials.", status: :see_other
  rescue Airtel::Client::Refused, JsonHttp::Unreachable => error
    redirect_to airtel_merchants_path, alert: "Couldn't connect: #{error.message}", status: :see_other
  end
end
