# Stock › Reorder: one page for what's running low. Staff who buy see it grouped by supplier with
# suggested quantities and one-click draft orders; everyone else sees what's below its reorder level.
class ReorderListsController < ApplicationController
  def show
    if current_membership.can_purchase?
      @suggestion = ReorderSuggestion.new(Current.account, selected_branch)
    else
      @products = Current.account.products.active.below_reorder_level_at(selected_branch)
        .includes(:unit, :category).select("products.*, COALESCE(stock_levels.quantity, 0) AS stock_quantity")
        .order(Arel.sql("COALESCE(stock_levels.quantity, 0) - products.reorder_level"), :name)
    end
  end
end
