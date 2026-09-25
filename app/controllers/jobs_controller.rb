class JobsController < ApplicationController
  FILTERS = %w[ open closed all ].freeze

  before_action :ensure_can_sell, except: %i[ index show ]
  before_action :ensure_can_sell_or_manage_receivables, only: %i[ index show ]
  before_action :set_job, only: %i[ show edit update ]

  def index
    @filter = params[:filter].presence_in(FILTERS) || "open"
    jobs = Current.account.jobs.recent_first.includes(:customer)
    jobs = jobs.where(status: @filter) unless @filter == "all"
    if params[:query].present?
      like = "%#{Job.sanitize_sql_like(params[:query].squish)}%"
      jobs = jobs.joins(:customer).where("jobs.name ILIKE :like OR jobs.site ILIKE :like OR jobs.reference ILIKE :like OR customers.name ILIKE :like", like: like)
    end
    @jobs = paginate(jobs)
    @spent = Job.spent_cents_by_id(@jobs.map(&:id))
  end

  def show
    @materials = @job.materials
    @sales = @job.sales.finished.chronologically.includes(:branch, :payments)
    @returns = @job.returns.includes(:branch, :sale).order(:created_at)
    @orders = @job.customer_orders.where.not(status: %w[ collected cancelled ]).chronologically.includes(:branch)
  end

  def new
    customer = Current.account.customers.find_by(id: params[:customer_id])
    @job = Current.account.jobs.new(customer: customer)
  end

  def create
    @job = Current.account.jobs.new(job_params)

    if @job.save
      redirect_to @job, notice: "Job #{@job.name} added for #{@job.customer.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @job.update(job_params)
      redirect_to @job, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_job
      @job = Current.account.jobs.find(params[:id])
    end

    # The customer is chosen when the job is added and stays: its sales are theirs.
    def job_params
      permitted = params.expect(job: %i[ customer_id name site reference budget note ])
      customer_id = permitted.delete(:customer_id)
      permitted[:customer] = Current.account.customers.find(customer_id) if @job.nil? && customer_id.present?
      permitted
    end
end
