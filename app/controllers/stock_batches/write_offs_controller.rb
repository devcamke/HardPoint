# Taking an expired or damaged batch off the shelf, so the stock matches what can be sold. Past the day's limit it
# needs an owner or manager (StockWriteOff).
class StockBatches::WriteOffsController < ApplicationController
  REASONS = %w[ expired damaged ].freeze

  before_action :ensure_can_manage_stock

  def create
    batch = within_visible_branches(Current.account.stock_batches).find(params[:stock_batch_id])
    reason = params[:reason].presence_in(REASONS) || "expired"
    quantity = params[:quantity].presence || batch.quantity
    write_off = StockWriteOff.new(product: batch.product, branch: batch.branch, quantity: quantity, reason: reason)
    approver = approver_for_action if write_off.needs_approval?
    return redirect_to(batch, alert: write_off.approval_needed_message) if write_off.needs_approval? && approver.nil?

    batch.write_off(quantity, reason: reason, note: params[:note].presence)
    write_off.approved(approver) if approver
    redirect_to batch, notice: "Written off as #{reason}."
  rescue ArgumentError => error
    redirect_to batch, alert: error.message
  end
end
