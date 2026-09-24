class HireAgreementsController < ApplicationController
  include Pagination
  before_action :ensure_can_sell
  before_action :set_hire_agreement, only: :show

  FILTERS = %w[ out overdue returned all ].freeze

  def index
    @filter = params[:filter].presence_in(FILTERS) || "out"
    agreements = Current.account.hire_agreements.includes(:customer, :branch, lines: :hire_item)
    agreements = case @filter
    when "out" then agreements.out.order(:due_back_at)
    when "overdue" then agreements.overdue.order(:due_back_at)
    when "returned" then agreements.returned.order(returned_at: :desc)
    else agreements.chronologically
    end
    agreements = agreements.where(customer_id: Current.account.customers.search(params[:query]).select(:id)) if params[:query].present?
    @hire_agreements = paginate(agreements)
    @overdue_count = Current.account.hire_agreements.overdue.count
  end

  def show
    @order = @hire_agreement.customer_order
  end

  def new
    @branch = hire_branch
    @available = Current.account.hire_items.available.where(branch: @branch).alphabetically
    @hire_agreement = Current.account.hire_agreements.new(branch: @branch, due_back_at: 1.day.from_now.change(min: 0))
  end

  def create
    @branch = hire_branch
    @hire_agreement = HireAgreement.hire_out(branch: @branch, customer: customer, items: Current.account.hire_items.where(id: params[:hire_item_ids]),
      due_back_at: Time.zone.parse(agreement_params[:due_back_at].to_s), **agreement_params.slice(:id_number, :site, :note).to_h.symbolize_keys)

    if @hire_agreement.persisted?
      redirect_to @hire_agreement, notice: "#{@hire_agreement.reference} is out. Take the #{helpers.money(@hire_agreement.deposit_due_cents)} deposit and print the agreement for signing.", status: :see_other
    else
      @available = Current.account.hire_items.available.where(branch: @branch).alphabetically
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => invalid
    @hire_agreement ||= Current.account.hire_agreements.new
    @hire_agreement.errors.add :base, invalid.record.errors.full_messages.to_sentence
    @available = Current.account.hire_items.available.where(branch: @branch).alphabetically
    render :new, status: :unprocessable_entity
  end

  private
    def set_hire_agreement
      @hire_agreement = Current.account.hire_agreements.find(params[:id])
    end

    def agreement_params
      params.fetch(:hire_agreement, {}).permit(:due_back_at, :id_number, :site, :note, :customer_id, :customer_name, :customer_phone)
    end

    def hire_branch
      Current.account.branches.find_by(id: params[:branch_id] || params.dig(:hire_agreement, :branch_id)) || current_till&.branch || selected_branch ||
        Current.account.branches.alphabetically.first
    end

    # An existing customer, or a new one from a name and phone number.
    def customer
      if agreement_params[:customer_id].present?
        Current.account.customers.find(agreement_params[:customer_id])
      elsif agreement_params[:customer_name].present?
        Current.account.customers.find_by_account_number(agreement_params[:customer_phone]) ||
          Current.account.customers.create!(name: agreement_params[:customer_name], phone: agreement_params[:customer_phone])
      end
    end
end
