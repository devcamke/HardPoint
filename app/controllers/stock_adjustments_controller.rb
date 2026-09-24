class StockAdjustmentsController < ApplicationController
  before_action :ensure_can_manage_stock

  def new
    @adjustment = Current.account.stock_adjustments.new(product: Current.account.products.find(params[:product_id]), branch: selected_branch)
  end

  def create
    @adjustment = Current.account.stock_adjustments.new(adjustment_params)

    if @adjustment.save
      redirect_to @adjustment.product, notice: "Stock at #{@adjustment.branch.name} is now #{helpers.quantity(@adjustment.product.stock_at(@adjustment.branch), @adjustment.product.unit)}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def adjustment_params
      permitted = params.expect(stock_adjustment: %i[ product_id branch_id reason quantity note ])
      permitted.merge(product: Current.account.products.find(permitted.delete(:product_id)),
        branch: Current.account.branches.find(permitted.delete(:branch_id)))
    end
end
