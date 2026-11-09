class StockTransfers::ReceiptsController < ApplicationController
  before_action :ensure_can_manage_stock

  def create
    transfer = Current.account.stock_transfers.find(params[:stock_transfer_id])

    if transfer.receive(received: params[:received]&.to_unsafe_h || {}, shortfall: params[:shortfall])
      redirect_to transfer, notice: "Received at #{transfer.to_branch.name}.#{" #{transfer.short_description.upcase_first}." if transfer.short?}", status: :see_other
    elsif transfer.errors.any?
      redirect_to transfer, alert: transfer.errors.full_messages.to_sentence, status: :see_other
    else
      redirect_to transfer, alert: "This transfer is already #{transfer.status.humanize.downcase}.", status: :see_other
    end
  end
end
