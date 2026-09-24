class Api::V1::CustomersController < Api::V1::BaseController
  before_action :set_customer, only: %i[ show update ]

  def index
    scope = Current.account.customers
    scope = scope.where(phone: params[:phone].to_s.gsub(/[^\d+]/, "")) if params[:phone].present?
    scope = scope.where(email: params[:email].to_s.strip.downcase) if params[:email].present?
    @customers = paginate(updated_since(scope))
  end

  def show
  end

  def create
    idempotently do
      @customer = Current.account.customers.create!(customer_params)
      render :show, status: :created
    end
  end

  def update
    @customer.update!(customer_params)
    render :show
  end

  private
    def set_customer
      @customer = Current.account.customers.find(params[:id])
    end

    # Credit limits and price lists stay with the shop's staff.
    def customer_params
      params.expect(customer: %i[ name phone email tax_pin address notes ])
    end
end
