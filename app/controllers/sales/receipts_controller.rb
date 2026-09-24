class Sales::ReceiptsController < ApplicationController
  include SaleScoped

  def show
    respond_to do |format|
      format.html { render layout: "receipt" }
      format.json { render json: ReceiptData.new(@sale) }
    end
  end
end
