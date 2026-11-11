class CustomerOrdersController < ApplicationController
  BLANK_LINES = 5
  STATUS_FILTERS = %w[ quote open ready collected cancelled ].freeze
  GROUPINGS = { "status" => "Status", "customer" => "Customer" }.freeze

  include ListGrouping

  before_action :ensure_can_sell
  before_action :set_customer_order, only: %i[ show edit update ]

  def index
    orders = within_visible_branches(Current.account.customer_orders).chronologically.includes(:customer, :branch)
    # "ordered" isn't offered as a filter (it's part of "open"), but opening the Ordered group picks it.
    @status = params[:status].presence_in(STATUS_FILTERS + [ "ordered", "all" ]) || "open"
    orders = case @status
    when "open" then orders.open
    when "all" then orders
    else orders.where(status: @status)
    end
    orders = orders.where(customer_id: Current.account.customers.search(params[:query]).select(:id)) if params[:query].present?
    orders = orders.where(customer: Current.account.customers.find(params[:customer_id])) if params[:customer_id].present?
    if (@group_by = params[:group_by].presence_in(GROUPINGS.keys))
      @groups = order_groups(orders)
    else
      @customer_orders = paginate(orders)
      balances = CustomerOrder.deposit_balances_by_id(@customer_orders.map(&:id))
      @customer_orders.each { _1.deposit_balance_cents = balances[_1.id] }
    end
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

    if @customer_order.save
      # Confirming straight away is confirming: an order past the customer's credit needs a manager, as on the quote.
      if params[:order_now] == "1" && !@customer_order.confirm(approver: approver_for_action)
        return redirect_to @customer_order, status: :see_other,
          alert: "Saved as quote #{@customer_order.reference}, not confirmed: #{@customer_order.errors.full_messages.to_sentence}."
      end
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
    if @customer_order.editable? && update_within_credit
      redirect_to @customer_order, notice: "Saved."
    else
      @customer_order.errors.add :base, "A #{@customer_order.status} order can't be changed" unless @customer_order.editable?
      add_blank_lines
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # Raising a confirmed order past the customer's credit, or moving it to a customer it takes past theirs, needs a
    # manager, as confirming it would have.
    def update_within_credit
      total_before, customer_before = @customer_order.total_cents, @customer_order.customer_id
      saved = false
      CustomerOrder.transaction do
        @customer_order.update(customer_order_params) or raise ActiveRecord::Rollback
        grew = @customer_order.total_cents > total_before || @customer_order.customer_id != customer_before
        if @customer_order.ordered? && grew && @customer_order.over_credit_limit?
          if (approver = approver_for_action)
            @customer_order.track_event "credit_approved", approver: approver, customer: @customer_order.customer.name,
              amount: @customer_order.balance_to_pay_cents, available: @customer_order.customer.available_credit_cents
          else
            @customer_order.errors.add :base, "#{@customer_order.customer.name} has only #{Money.format(@customer_order.customer.available_credit_cents)} " \
              "of credit left. An order of #{Money.format(@customer_order.balance_to_pay_cents)} for them needs a manager's approval PIN"
            raise ActiveRecord::Rollback
          end
        end
        saved = true
      end
      saved
    end

    def order_groups(orders)
      if @group_by == "status"
        list_groups(orders, :status, labels: ->(status) { status.humanize }, total: :total_cents, currency: Current.account.currency,
          order: CustomerOrder.statuses.keys)
      else
        names = Current.account.customers.where(id: orders.select(:customer_id)).pluck(:id, :name).to_h
        list_groups(orders, :customer_id, labels: names.method(:[]), total: :total_cents, currency: Current.account.currency)
      end
    end

    def set_customer_order
      @customer_order = within_visible_branches(Current.account.customer_orders).find(params[:id])
    end

    def customer_order_params
      permitted = params.expect(customer_order: [ :customer_id, :job_id, :fundi_id, :branch_id, :valid_until, :needed_by, :note,
        lines_attributes: [ [ :id, :product_code, :quantity, :unit_price, :_destroy ] ] ])
      permitted[:customer] = Current.account.customers.find(permitted.delete(:customer_id)) if permitted[:customer_id].present?
      permitted[:job] = permitted[:job_id].present? ? Current.account.jobs.find(permitted[:job_id]) : nil if permitted.key?(:job_id)
      permitted.delete(:job_id)
      permitted[:fundi] = permitted[:fundi_id].present? ? Current.account.fundis.find(permitted[:fundi_id]) : nil if permitted.key?(:fundi_id)
      permitted.delete(:fundi_id)
      permitted[:branch] = visible_branches.find(permitted.delete(:branch_id)) if permitted.key?(:branch_id)
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
