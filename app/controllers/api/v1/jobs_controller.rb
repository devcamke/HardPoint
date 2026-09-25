# Contractors' jobs, read-only: they're set up in the shop.
class Api::V1::JobsController < Api::V1::BaseController
  def index
    scope = Current.account.jobs
    scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    @jobs = paginate(updated_since(scope))
    @spent = Job.spent_cents_by_id(@jobs.map(&:id))
  end

  def show
    @job = Current.account.jobs.find(params[:id])
    @spent = { @job.id => @job.spent_cents }
  end
end
