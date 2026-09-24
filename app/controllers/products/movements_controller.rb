class Products::MovementsController < ApplicationController
  include ProductScoped

  def index
    @movements = paginate(@product.stock_movements.chronologically.includes(:branch, :creator))
  end
end
