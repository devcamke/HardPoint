# Fundis who bring customers to the shop: the list with what each is owed, a fundi's commission statement, and
# adding or editing one. Anyone who sells can add a fundi at the counter; their own commission rate is for owners
# and managers to agree.
class FundisController < ApplicationController
  FILTERS = %w[ active inactive all ].freeze

  before_action :ensure_can_sell, except: %i[ index show ]
  before_action :ensure_can_sell_or_manage_receivables, only: %i[ index show ]
  before_action :set_fundi, only: %i[ show edit update ]

  def index
    @filter = params[:filter].presence_in(FILTERS) || "active"
    fundis = Current.account.fundis.search(params[:query]).alphabetically
    fundis = fundis.where(active: @filter == "active") unless @filter == "all"
    @fundis = paginate(fundis)
    ids = @fundis.map(&:id)
    @owed = Fundi.balances_by_id(ids)
    month = FundiEntry.where(fundi_id: ids, kind: %w[ earned reversed ], created_at: Time.zone.today.beginning_of_month.beginning_of_day..)
    @brought = month.group(:fundi_id).sum(:sales_cents)
    @earned = month.group(:fundi_id).sum(:amount_cents)
    @total_owed = Fundi.balances_by_id.values.select(&:positive?).sum
  end

  def show
    @entries = @fundi.entries.chronologically.includes(:source, :creator).to_a
    @balance = @entries.sum(&:amount_cents)
    @brought = @entries.select { _1.kind != "paid" }.sum(&:sales_cents)
  end

  def new
    @fundi = Current.account.fundis.new(name: params[:name], phone: params[:phone])
  end

  def create
    @fundi = Current.account.fundis.new(fundi_params)
    if @fundi.save
      redirect_to(params[:for_till].present? ? pos_path : @fundi, notice: "#{@fundi.name} added.")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @fundi.update(fundi_params)
      redirect_to @fundi, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_fundi
      @fundi = Current.account.fundis.find(params[:id])
    end

    def fundi_params
      fields = %i[ name phone trade note active ]
      fields << :commission_percent if current_membership.approver?
      permitted = params.expect(fundi: fields)
      permitted[:commission_percent] = permitted[:commission_percent].presence if permitted.key?(:commission_percent)
      permitted
    end
end
