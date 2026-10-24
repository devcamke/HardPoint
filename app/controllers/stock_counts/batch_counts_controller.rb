# Counting one batch of a batch-tracked product, or a batch found on the shelf that the take didn't expect.
class StockCounts::BatchCountsController < ApplicationController
  include StockCountScoped
  before_action :ensure_can_manage_stock, :ensure_counting

  def create
    @line = @count.lines.includes(product: :unit).find(params[:line_id])
    row = @line.count_batch(number: params[:number], quantity: params[:counted_quantity].presence, expires_on: params[:expires_on])
    @error = row.errors.full_messages.to_sentence if row.errors.any?
    @line.reload

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@line, partial: "stock_counts/line", locals: { line: @line, count: @count, error: @error }) }
      format.html { redirect_back_or_to @count, alert: @error }
    end
  end
end
