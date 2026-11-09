class SaleReturnsController < ApplicationController
  before_action :ensure_can_sell

  def index
    @returns = paginate(within_visible_branches(Current.account.sale_returns).chronologically.includes(:sale, :creator, :branch))
  end

  def show
    @return = within_visible_branches(Current.account.sale_returns).find(params[:id])
    render layout: "receipt" if params[:print]
  end
end
