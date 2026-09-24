class ReorderListsController < ApplicationController
  def show
    @products = Current.account.products.active.below_reorder_level_at(selected_branch)
      .includes(:unit, :category).select("products.*, COALESCE(stock_levels.quantity, 0) AS stock_quantity")
      .order(Arel.sql("COALESCE(stock_levels.quantity, 0) - products.reorder_level"), :name)
  end
end
