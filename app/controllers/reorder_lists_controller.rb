# Stock › Reorder: one page for what's running low. Staff who buy see it grouped by supplier with
# suggested quantities and one-click draft orders; everyone else sees what's below its reorder level.
class ReorderListsController < ApplicationController
  def show
    # Stock another branch can spare comes first: moving it is quicker than ordering.
    @rebalancing = BranchRebalancing.new(Current.account) if Current.account.branches.many?
    if current_membership.can_purchase?
      @suggestion = ReorderSuggestion.new(Current.account, selected_branch)
    else
      @products = Current.account.products.active.below_reorder_level_at(selected_branch).most_short_first.includes(:unit, :category).order(:name)
    end
  end
end
