class StockTransfers::ReceiptsController < ApplicationController
  before_action :ensure_can_manage_stock

  def create
    transfer = Current.account.stock_transfers.find(params[:stock_transfer_id])

    if transfer.receive
      redirect_to transfer, notice: "Received at #{transfer.to_branch.name}.", status: :see_other
    else
      redirect_to transfer, alert: "This transfer is already #{transfer.status.humanize.downcase}.", status: :see_other
    end
  end
end
