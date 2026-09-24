class StockTransfersController < ApplicationController
  BLANK_LINES = 8

  before_action :ensure_can_manage_stock, only: %i[ new create ]

  def index
    @transfers = paginate(Current.account.stock_transfers.chronologically.includes(:from_branch, :to_branch, :sender, :lines))
  end

  def show
    @transfer = Current.account.stock_transfers.find(params[:id])
  end

  def new
    @transfer = Current.account.stock_transfers.new(from_branch: selected_branch)
    BLANK_LINES.times { @transfer.lines.build }
  end

  def create
    @transfer = Current.account.stock_transfers.new(transfer_params)

    if @transfer.save
      redirect_to @transfer, notice: "Sent. Stock left #{@transfer.from_branch.name} and is in transit."
    else
      (BLANK_LINES - @transfer.lines.size).clamp(1, BLANK_LINES).times { @transfer.lines.build }
      render :new, status: :unprocessable_entity
    end
  end

  private
    def transfer_params
      permitted = params.expect(stock_transfer: [ :from_branch_id, :to_branch_id, :note, lines_attributes: [ [ :product_code, :quantity ] ] ])
      permitted.merge(from_branch: Current.account.branches.find(permitted.delete(:from_branch_id)),
        to_branch: Current.account.branches.find(permitted.delete(:to_branch_id)))
    end
end
