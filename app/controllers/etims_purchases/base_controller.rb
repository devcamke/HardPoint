# What's done with one invoice from KRA: each action is its own small controller under this one.
class EtimsPurchases::BaseController < ApplicationController
  before_action :set_purchase

  private
    def set_purchase
      devices = within_visible_branches(Current.account.etims_devices).select(:id)
      @purchase = Current.account.etims_purchases.where(device_id: devices).find(params[:etims_purchase_id])
    end

    def back_with_errors
      redirect_to @purchase, alert: @purchase.errors.full_messages.to_sentence, status: :see_other
    end
end
