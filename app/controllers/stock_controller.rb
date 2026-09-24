class StockController < ApplicationController
  def show
    @valuation = StockValuation.new(Current.account)
    @low_stock_count = Current.account.products.active.below_reorder_level_at(selected_branch).count
    @in_transit = Current.account.stock_transfers.in_transit.count
    @open_counts = Current.account.stock_counts.where(status: %w[ counting submitted ]).count
    @movements = Current.account.stock_movements.chronologically.includes(:branch, :creator, :product).limit(10)
  end
end
