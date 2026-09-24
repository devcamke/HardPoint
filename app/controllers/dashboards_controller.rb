class DashboardsController < ApplicationController
  def show
    @branches = Current.account.branches.alphabetically
    @memberships = Current.account.memberships.includes(:user)
    @registers_count = Current.account.registers.active.count
  end
end
