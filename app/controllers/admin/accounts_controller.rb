class Admin::AccountsController < Admin::BaseController
  around_action :across_accounts

  def index
    @accounts = Account.order(created_at: :desc)
    @member_counts = Membership.group(:account_id).count
    @branch_counts = Branch.group(:account_id).count
  end

  def show
    @account = Account.find(params[:id])
    @memberships = @account.memberships.alphabetically.includes(:user)
    @branches = @account.branches.alphabetically
    @events = @account.account_events.chronologically.includes(:creator).limit(20)
  end
end
