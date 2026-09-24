class DashboardsController < ApplicationController
  def show
    @branches = Current.account.branches.alphabetically
    @memberships = Current.account.memberships.includes(:user)
  end
end
