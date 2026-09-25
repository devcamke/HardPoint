class CustomerOrdersController < ApplicationController
  BLANK_LINES = 5
  STATUS_FILTERS = %w[ quote open ready collected cancelled ].freeze

  before_action :ensure_can_sell
  before_action :set_customer_order, only: %i[ show edit update ]

  def index
    orders = Current.account.customer_orders.chronologically.includes(:customer, :branch)
    @status = params[:status].presence_in(STATUS_FILTERS + [ "all" ]) || "open"
    orders = case @status
    when "open" then orders.open
    when "all" then orders
    else orders.where(status: @status)
    end
    orders = orders.where(customer_id: Current.account.customers.search(params[:query]).select(:id)) if params[:query].present?
    @customer_orders = paginate(orders)
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        pdf = CustomerOrderPdf.new(@customer_order)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end

  def new
    job = Current.account.jobs.open.find_by(id: params[:job_id]) if params[:job_id]
    @customer_order = Current.account.customer_orders.new(branch: current_till&.branch || selected_branch,
      customer: job&.customer || Current.account.customers.find_by(id: params[:customer_id]), job: job)
    add_blank_lines
  end

  def create
    @customer_order = Current.account.customer_orders.new(customer_order_params)
    @customer_order.status = :ordered if params[:order_now] == "1"
    @customer_order.ordered_at = Time.current if @customer_order.ordered?

    if @customer_order.save
      redirect_to @customer_order, notice: "#{@customer_order.kind} #{@customer_order.reference} saved."
    else
      add_blank_lines
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return redirect_to @customer_order, alert: "A #{@customer_order.status} order can't be changed." unless @customer_order.editable?
    add_blank_lines
  end

  def update
    if @customer_order.editable? && @customer_order.update(customer_order_params)
      redirect_to @customer_order, notice: "Saved."
    else
      @customer_order.errors.add :base, "A #{@customer_order.status} order can't be changed" unless @customer_order.editable?
      add_blank_lines
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_customer_order
      @customer_order = Current.account.customer_orders.find(params[:id])
    end

    def customer_order_params
      permitted = params.expect(customer_order: [ :customer_id, :job_id, :branch_id, :valid_until, :needed_by, :note,
        lines_attributes: [ [ :id, :product_code, :quantity, :unit_price, :_destroy ] ] ])
      permitted[:customer] = Current.account.customers.find(permitted.delete(:customer_id)) if permitted[:customer_id].present?
      permitted[:job] = permitted[:job_id].present? ? Current.account.jobs.find(permitted[:job_id]) : nil if permitted.key?(:job_id)
      permitted.delete(:job_id)
      permitted[:branch] = Current.account.branches.find(permitted.delete(:branch_id)) if permitted.key?(:branch_id)
      permitted[:lines_attributes]&.each_value do |line|
        line[:account] = Current.account if line[:id].blank?
        # Only owners and managers set prices by hand; everyone else quotes the customer's own prices.
        line.delete(:unit_price) unless current_membership.approver?
      end
      permitted
    end

    def add_blank_lines
      (BLANK_LINES - @customer_order.lines.count(&:new_record?)).clamp(1, BLANK_LINES).times { @customer_order.lines.build }
    end
end
