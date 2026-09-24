# The tools a shop hires out (managers look after the list; anyone who sells can hire them out).
class HireItemsController < ApplicationController
  before_action :ensure_can_manage_catalogue, except: :index
  before_action :ensure_can_sell, only: :index
  before_action :set_hire_item, only: %i[ edit update destroy ]

  def index
    @status = params[:status].presence_in(HireItem::STATUSES)
    items = Current.account.hire_items.alphabetically.includes(:branch)
    items = items.where(status: @status) if @status
    @hire_items = items
    @counts = Current.account.hire_items.group(:status).count
    @earned = HireLine.where(hire_item_id: @hire_items.map(&:id), returned_at: 90.days.ago..).group(:hire_item_id).sum("charge_cents + damage_cents")
    @current_hires = HireAgreement.out.joins(:lines).where(hire_lines: { hire_item_id: @hire_items.map(&:id), returned_at: nil })
      .select("hire_agreements.*, hire_lines.hire_item_id AS item_id").index_by(&:item_id)
  end

  def new
    @hire_item = Current.account.hire_items.new(branch: selected_branch || Current.account.branches.alphabetically.first)
  end

  def create
    @hire_item = Current.account.hire_items.new(hire_item_params)
    if @hire_item.save
      redirect_to hire_items_path, notice: "#{@hire_item.label} added.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hire_item.update(hire_item_params)
      redirect_to hire_items_path, notice: "#{@hire_item.label} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # A tool that's been hired stays on record (retire it instead); one never hired can go.
  def destroy
    if @hire_item.hire_lines.exists?
      @hire_item.update!(status: "retired")
      redirect_to hire_items_path, notice: "#{@hire_item.label} retired; its hire history is kept.", status: :see_other
    else
      @hire_item.destroy!
      redirect_to hire_items_path, notice: "#{@hire_item.label} removed.", status: :see_other
    end
  end

  private
    def set_hire_item
      @hire_item = Current.account.hire_items.find(params[:id])
    end

    def hire_item_params
      permitted = params.expect(hire_item: %i[ name asset_tag serial_number branch_id daily_rate weekly_rate deposit status notes ])
      permitted[:branch_id] = Current.account.branches.find(permitted[:branch_id]).id if permitted[:branch_id].present?
      permitted[:status] = nil if permitted[:status] == "on_hire" || @hire_item&.on_hire? # set by hiring and returns, not by hand
      permitted.compact_blank.merge(permitted.slice(:weekly_rate, :serial_number, :notes))
    end
end
