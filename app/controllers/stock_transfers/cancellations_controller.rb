class StockTransfers::CancellationsController < ApplicationController
  before_action :ensure_can_manage_stock

  def create
    transfer = Current.account.stock_transfers.find(params[:stock_transfer_id])

    if transfer.cancel
      redirect_to transfer, notice: "Cancelled. The stock is back at #{transfer.from_branch.name}.", status: :see_other
    else
      redirect_to transfer, alert: "This transfer is already #{transfer.status.humanize.downcase}.", status: :see_other
    end
  end
end
