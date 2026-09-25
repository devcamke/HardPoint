# Taking an expired or damaged batch off the shelf, so the stock matches what can be sold.
class StockBatches::WriteOffsController < ApplicationController
  REASONS = %w[ expired damaged ].freeze

  before_action :ensure_can_manage_stock

  def create
    batch = Current.account.stock_batches.find(params[:stock_batch_id])
    reason = params[:reason].presence_in(REASONS) || "expired"
    batch.write_off(params[:quantity].presence || batch.quantity, reason: reason, note: params[:note].presence)
    redirect_to batch, notice: "Written off as #{reason}."
  rescue ArgumentError => error
    redirect_to batch, alert: error.message
  end
end
