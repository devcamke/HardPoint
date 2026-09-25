class StockMovementsController < ApplicationController
  def index
    movements = Current.account.stock_movements.chronologically.includes(:branch, :creator, :product, :stock_batch)
    movements = movements.where(branch: selected_branch) if params[:all_branches] != "1"
    movements = movements.where(reason: params[:reason]) if params[:reason].in?(StockMovement::REASONS)
    @movements = paginate(movements)
  end
end
