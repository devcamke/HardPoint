# Put the current sale aside (the customer went to fetch something) and serve the next one.
class Pos::ParkingsController < ApplicationController
  include PosSale

  def create
    if @sale.payments.any?
      redirect_to pos_path, alert: "A sale with payments can't be parked. Finish it or remove the payments."
    elsif @sale.park
      redirect_to pos_path, notice: "Sale parked. Recall it from Parked sales."
    else
      redirect_to pos_path, alert: "Nothing to park."
    end
  end
end
