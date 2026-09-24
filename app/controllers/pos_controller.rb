class PosController < ApplicationController
  include PosSale

  layout "pos"

  def show
    @sale.reload_for_cart
    @completed_sale = current_shift.sales.completed.find_by(id: params[:completed])
  end
end
