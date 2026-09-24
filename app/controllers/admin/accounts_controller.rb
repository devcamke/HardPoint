class Admin::AccountsController < Admin::BaseController
  around_action :across_accounts

  def index
    @status = params[:status].presence_in(Account::Subscription::STATUSES)
    @accounts = Account.order(created_at: :desc)
    @accounts = @accounts.where(subscription_status: @status) if @status
    @status_counts = Account.group(:subscription_status).count
    @member_counts = Membership.group(:account_id).count
    @branch_counts = Branch.group(:account_id).count
    @product_counts = Product.where(active: true).group(:account_id).count
    @sales_counts = Sale.completed.where(completed_at: 30.days.ago..).group(:account_id).count
    @monthly_revenue_cents = Account.where(subscription_status: %w[ active payment_due ]).pluck(:plan).sum { Plan.find(_1).price_cents }
    @paid_last_30_days_cents = Billing::Invoice.paid.where(paid_at: 30.days.ago..).sum(:amount_cents)
  end

  def show
    @account = Account.find(params[:id])
    @memberships = @account.memberships.alphabetically.includes(:user)
    @branches = @account.branches.alphabetically
    @events = @account.account_events.chronologically.includes(:creator).limit(20)
    @invoices = @account.billing_invoices.limit(12)
    @support_requests = @account.support_requests.chronologically.includes(:user).limit(10)
    @usage = @account.usage
    @sales_last_30_days = @account.sales.completed.where(completed_at: 30.days.ago..).count
  end
end
