class StockCounts::SubmissionsController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_manage_stock

  def create
    if @count.submit
      redirect_to @count, notice: "Submitted for approval.", status: :see_other
    else
      redirect_to @count, alert: "Only a stock take in progress can be submitted.", status: :see_other
    end
  end
end
