class Sales::ReceiptsController < ApplicationController
  include SaleScoped

  def show
    render layout: "receipt"
  end
end
