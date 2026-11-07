class DashboardsController < ApplicationController
  def show
    if current_membership&.can_view_reports?
      @branch = Current.account.branches.find_by(id: params[:branch_id])
      @dashboard = Dashboard.new(Current.account, branch: @branch)
      @branches = Current.account.branches.alphabetically
    else
      # Staff without reports start where their work is. On a counter computer whose till is set to open
      # straight into selling, that's the till itself.
      return redirect_to pos_path if current_till&.opens_till? && current_membership.can_sell? && params[:home].blank?

      mine = Current.account.sales.where(cashier: Current.user)
      today = mine.completed.where(completed_at: Time.zone.today.all_day)
      @my_sales_today_cents = today.sum(:total_cents)
      @my_sales_today_count = today.count
      @parked_count = mine.parked.count
      @orders_ready_count = Current.account.customer_orders.ready.where(branch: selected_branch).count
      @low_stock_count = Current.account.products.active.below_reorder_level_at(selected_branch).count
    end
  end
end
