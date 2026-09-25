# Batches with expiry dates: what's expired or expiring at a branch, and one batch's history,
# including who bought from it (for a recall).
class StockBatchesController < ApplicationController
  FILTERS = %w[ expiring expired all ].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS) || "expiring"
    batches = Current.account.stock_batches.in_stock.where(branch: selected_branch).includes(product: :unit).by_expiry
    @batches = case @filter
    when "expiring" then batches.where(expires_on: ..(Date.current + StockBatch::EXPIRING_WITHIN))
    when "expired" then batches.expired
    else batches
    end
    @batches = paginate(@batches)
  end

  def show
    @batch = Current.account.stock_batches.find(params[:id])
    @movements = @batch.stock_movements.includes(:branch, :product, :creator, :stock_batch).chronologically
    @sales = @batch.sales.completed.includes(:customer, :branch).order(completed_at: :desc)
    @other_branches = Current.account.stock_batches.where(product: @batch.product, number: @batch.number).where.not(id: @batch.id).includes(:branch)
  end
end
