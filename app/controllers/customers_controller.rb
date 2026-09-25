class CustomersController < ApplicationController
  before_action :ensure_can_sell, except: %i[ index show ]
  before_action :ensure_can_sell_or_manage_receivables, only: %i[ index show ]
  before_action :set_customer, only: %i[ show edit update ]

  def index
    @customers = paginate(Current.account.customers.search(params[:query]).alphabetically.includes(:price_list))
  end

  def show
    @sales = @customer.sales.finished.chronologically.limit(20)
    @orders = @customer.customer_orders.where.not(status: %w[ collected cancelled ]).chronologically.includes(:branch)
    @open_invoices = @customer.open_invoices
    @payments = @customer.customer_payments.chronologically.limit(10).includes(:creator)
    @loyalty = Current.account.loyalty_program if Current.account.loyalty_program&.enabled? || @customer.loyalty_entries.exists?
    @points = @customer.loyalty_entries.chronologically.includes(:sale, :sale_return).limit(10) if @loyalty
    @jobs = @customer.jobs.open.alphabetically
    @job_spend = Job.spent_cents_by_id(@jobs.map(&:id))
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
      permitted = %i[ name phone email tax_pin address notes ]
      permitted += %i[ price_list_id credit_limit payment_terms_days ] if current_membership.approver?
      params.expect(customer: permitted)
    end
end
