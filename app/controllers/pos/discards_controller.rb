class Pos::DiscardsController < ApplicationController
  include PosSale

  def create
    if @sale.discard
      redirect_to pos_path, notice: "Sale cleared."
    else
      redirect_to pos_path, alert: @sale.errors.full_messages.to_sentence.presence || "This sale can't be cleared."
    end
  end
end
