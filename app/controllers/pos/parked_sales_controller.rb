class Pos::ParkedSalesController < ApplicationController
  include PosSale

  layout "pos"

  def index
    @parked = current_shift.sales.parked.includes(:customer, :cashier, :lines).order(updated_at: :desc)
  end
end
