class StockCounts::LinesController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_manage_stock, :ensure_counting

  def update
    @line = @count.lines.find(params[:id])
    if @line.by_batch?
      @line.errors.add :base, "Count #{@line.product.name} batch by batch"
    else
      @line.update(counted_quantity: params.dig(:stock_count_line, :counted_quantity).presence)
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@line, partial: "stock_counts/line", locals: { line: @line, count: @count }) }
      format.html { redirect_back_or_to @count }
    end
  end
end
