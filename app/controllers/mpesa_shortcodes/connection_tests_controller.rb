# Checks the Daraja credentials by asking Safaricom for a token.
class MpesaShortcodes::ConnectionTestsController < ApplicationController
  before_action :ensure_can_manage_account

  def create
    shortcode = Current.account.mpesa_shortcodes.find(params[:mpesa_shortcode_id])
    shortcode.test_connection
    redirect_to mpesa_shortcodes_path, notice: "Connected to Safaricom: #{shortcode.label} is ready.", status: :see_other
  rescue Mpesa::Client::Refused, JsonHttp::Unreachable => error
    redirect_to mpesa_shortcodes_path, alert: "Couldn't connect: #{error.message}", status: :see_other
  end
end
