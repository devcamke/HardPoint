class SalesController < ApplicationController
  before_action :ensure_can_sell

  def index
    sales = Current.account.sales.finished.chronologically.includes(:branch, :customer, :cashier, :register)
    if params[:query].present?
      sales = sales.where(id: Current.account.sales.find_by_receipt_number(params[:query])&.id)
    else
      @date = (Date.parse(params[:date]) rescue Time.zone.today)
      sales = sales.where(completed_at: @date.all_day)
      # At a till, show its branch; elsewhere, every branch — unless one is picked.
      @branch = params.key?(:branch_id) ? Current.account.branches.find_by(id: params[:branch_id]) : current_till&.branch
      sales = sales.where(branch: @branch) if @branch
    end
    @sales = paginate(sales)
  end

  def show
    @sale = Current.account.sales.find(params[:id])
  end
end
