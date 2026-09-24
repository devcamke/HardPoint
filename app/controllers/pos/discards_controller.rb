class Pos::DiscardsController < ApplicationController
  include PosSale

  def create
    if @sale.discard
      redirect_to pos_path, notice: "Sale cleared."
    else
      redirect_to pos_path, alert: "Remove the payments before clearing this sale."
    end
  end
end
