class SaleReturnsController < ApplicationController
  before_action :ensure_can_sell

  def index
    @returns = paginate(Current.account.sale_returns.chronologically.includes(:sale, :creator, :branch))
  end

  def show
    @return = Current.account.sale_returns.find(params[:id])
    render layout: "receipt" if params[:print]
  end
end
