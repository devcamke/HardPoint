# Signs what QZ Tray asks to be signed (SHA-512 with RSA) with the shop's own key, so the shop's tills trust the
# till's print requests and nobody else's do (Account::QzSigning). Only for a till set up to print through QZ Tray.
class QzSignaturesController < ApplicationController
  before_action :ensure_can_sell
  rate_limit to: 600, within: 1.minute

  def create
    return head(:forbidden) unless current_till&.print_mode == "qz_tray"

    render plain: Current.account.qz_sign(params[:request])
  end
end
