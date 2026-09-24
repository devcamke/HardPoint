class DashboardsController < ApplicationController
  def show
    if current_membership&.can_view_reports?
      @branch = Current.account.branches.find_by(id: params[:branch_id])
      @dashboard = Dashboard.new(Current.account, branch: @branch)
    end

    @branches = Current.account.branches.alphabetically
    @memberships = Current.account.memberships.includes(:user)
    @registers_count = Current.account.registers.active.count
    @products_count = Current.account.products.active.count
    today = Current.account.sales.completed.where(completed_at: Time.zone.today.all_day)
    @sales_today_cents = today.sum(:total_cents)
    @sales_today_count = today.count
    @low_stock_count = Current.account.products.active.below_reorder_level_at(selected_branch).count
  end
end
