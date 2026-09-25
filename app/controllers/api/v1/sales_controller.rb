# Completed and voided sales, read-only: they're made at the till.
class Api::V1::SalesController < Api::V1::BaseController
  def index
    scope = Current.account.sales.where(status: %w[ completed voided ]).includes(:branch, :register, :cashier, :customer, :payments, lines: :product)
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.where(job_id: params[:job_id]) if params[:job_id].present?
    @sales = paginate(updated_since(scope))
  end

  def show
    @sale = Current.account.sales.where(status: %w[ completed voided ]).find(params[:id])
  end
end
