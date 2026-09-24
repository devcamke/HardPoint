# Registers where Safaricom sends payments made straight to the Paybill or Till.
class MpesaShortcodes::C2bRegistrationsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    shortcode = Current.account.mpesa_shortcodes.find(params[:mpesa_shortcode_id])
    shortcode.register_c2b_urls
    redirect_to mpesa_shortcodes_path, notice: "Payments to #{shortcode.label} will now show up in HardPoint.", status: :see_other
  rescue Mpesa::Client::Refused, JsonHttp::Unreachable => error
    redirect_to mpesa_shortcodes_path, alert: "Safaricom didn't register it: #{error.message}", status: :see_other
  end
end
