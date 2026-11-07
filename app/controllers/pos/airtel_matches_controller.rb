# Using an Airtel Money payment that arrived after the till stopped waiting for it.
class Pos::AirtelMatchesController < ApplicationController
  include PosSale

  def create
    request = Current.account.airtel_requests.unused.find(params[:request_id])
    payment = request.use_on(@sale)
    if payment&.persisted?
      redirect_to(@sale.reload.completed? ? pos_path(completed: @sale.id) : pos_path, notice: "Airtel Money #{request.airtel_money_id} used on this sale.")
    else
      redirect_to pos_path, alert: "Couldn't use it: #{payment&.errors&.full_messages&.to_sentence || "already used"}"
    end
  end
end
