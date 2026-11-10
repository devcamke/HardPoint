class StockController < ApplicationController
  def show
    @valuation = StockValuation.new(Current.account, branches: (visible_branches if current_membership&.bound_to_branch?))
    @low_stock_count = Current.account.products.active.below_reorder_level_at(selected_branch).count
    @in_transit = visible_transfers.in_transit.count
    @below_zero = Current.account.stock_levels.where(branch: selected_branch).where("quantity < 0").count
    @open_counts = within_visible_branches(Current.account.stock_counts).where(status: %w[ counting submitted ]).count
    @expiring = Current.account.stock_batches.in_stock.where(branch: selected_branch, expires_on: ..(Date.current + StockBatch::EXPIRING_WITHIN)).count if Current.account.products.exists?(tracks_batches: true)
    @movements = within_visible_branches(Current.account.stock_movements).chronologically.includes(:branch, :creator, :product, :stock_batch).limit(10)
  end
end
