# Stock on hand of each product at each branch.
class Api::V1::StockLevelsController < Api::V1::BaseController
  def index
    scope = Current.account.stock_levels.includes(:product)
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    scope = scope.where(product_id: params[:product_id]) if params[:product_id].present?
    @stock_levels = paginate(updated_since(scope))
  end
end
