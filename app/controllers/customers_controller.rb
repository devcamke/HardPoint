class CustomersController < ApplicationController
  before_action :ensure_can_sell
  before_action :set_customer, only: %i[ show edit update ]

  def index
    @customers = paginate(Current.account.customers.search(params[:query]).alphabetically.includes(:price_list))
  end

  def show
    @sales = @customer.sales.finished.chronologically.limit(20)
  end

  def new
    @customer = Current.account.customers.new
  end

  def create
    @customer = Current.account.customers.new(customer_params)

    if @customer.save
      redirect_to @customer, notice: "#{@customer.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_customer
      @customer = Current.account.customers.find(params[:id])
    end

    # Only owners and managers decide who buys on credit and at what prices.
    def customer_params
      permitted = %i[ name phone email tax_pin notes ]
      permitted += %i[ price_list_id credit_limit ] if current_membership.approver?
      params.expect(customer: permitted)
    end
end
