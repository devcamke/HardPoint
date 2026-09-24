class PosController < ApplicationController
  include PosSale

  layout "pos"

  def show
    @completed_sale = current_shift.sales.completed.find_by(id: params[:completed])
  end
end
