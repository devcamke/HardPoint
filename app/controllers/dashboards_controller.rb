class DashboardsController < ApplicationController
  def show
    @branches = Current.account.branches.alphabetically
    @memberships = Current.account.memberships.includes(:user)
    @registers_count = Current.account.registers.active.count
    @products_count = Current.account.products.active.count
    @low_stock_count = Current.account.products.active.below_reorder_level_at(selected_branch).count
  end
end
