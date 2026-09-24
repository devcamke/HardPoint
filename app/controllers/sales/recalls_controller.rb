class Sales::RecallsController < ApplicationController
  include SaleScoped

  def create
    if @sale.shift != current_shift
      redirect_to pos_parked_sales_path, alert: "That sale was parked on another till."
    elsif @sale.recall
      redirect_to pos_path, notice: "Sale recalled."
    else
      redirect_to pos_parked_sales_path, alert: "Park or finish the sale you're on before recalling another."
    end
  end
end
