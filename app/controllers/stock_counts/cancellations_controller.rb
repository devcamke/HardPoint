class StockCounts::CancellationsController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_manage_stock

  def create
    if @count.cancel
      redirect_to @count, notice: "Stock take cancelled. Nothing was changed.", status: :see_other
    else
      redirect_to @count, alert: "This stock take can't be cancelled.", status: :see_other
    end
  end
end
