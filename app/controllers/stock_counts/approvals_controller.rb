class StockCounts::ApprovalsController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_approve_stock_counts

  def create
    if @count.approve
      redirect_to @count, notice: "Approved. Stock levels have been corrected.", status: :see_other
    else
      redirect_to @count, alert: "Only a submitted stock take can be approved.", status: :see_other
    end
  end
end
