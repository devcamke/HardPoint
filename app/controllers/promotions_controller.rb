# Offers on the shelf: anyone at the till can see what's running; owners and managers set them up.
class PromotionsController < ApplicationController
  FILTERS = %w[ running upcoming ended all ].freeze

  before_action :ensure_approver, except: %i[ index show ]
  before_action :set_promotion, only: %i[ show edit update destroy ]

  def index
    @filter = params[:filter].presence_in(FILTERS) || "running"
    today = Date.current
    promotions = Current.account.promotions.newest_first
    promotions = case @filter
    when "running" then promotions.running(today)
    when "upcoming" then promotions.where(starts_on: (today + 1)..)
    when "ended" then promotions.where(ends_on: ...today)
    else promotions
    end
    @promotions = paginate(promotions)
    @results = Promotion::Results.for(@promotions)
  end

  def show
    @results = Promotion::Results.for([ @promotion ])[@promotion.id]
    @products = @promotion.products.includes(:unit).alphabetically.limit(50)
  end

  def new
    @promotion = Current.account.promotions.new(kind: "percent_off", starts_on: Date.current, ends_on: Date.current + 7,
      product_ids: Array(params[:product_id]).compact)
  end

  def create
    @promotion = Current.account.promotions.new(promotion_params)
    if save_promotion
      redirect_to @promotion, notice: "#{@promotion.name} saved: #{@promotion.offer}, #{@promotion.status.humanize.downcase}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @promotion.assign_attributes(promotion_params)
    if save_promotion
      redirect_to @promotion, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Used promotions are kept for their results; ending one stops it today.
  def destroy
    if @promotion.sale_lines.exists?
      @promotion.update!(ends_on: [ Date.yesterday, @promotion.starts_on ].max, active: false)
      redirect_to @promotion, notice: "#{@promotion.name} ended."
    else
      @promotion.destroy!
      redirect_to promotions_path, notice: "#{@promotion.name} deleted."
    end
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end

    # Codes that match no product are reported rather than quietly left out.
    def save_promotion
      return @promotion.save if @missing_codes.blank?

      @promotion.valid?
      @promotion.errors.add :base, "No product with SKU or barcode #{@missing_codes.map { "“#{_1}”" }.to_sentence}"
      false
    end

    def set_promotion
      @promotion = Current.account.promotions.find(params[:id])
    end

    def promotion_params
      permitted = params.expect(promotion: [ :name, :kind, :percent_off, :buy_quantity, :free_quantity, :starts_on, :ends_on, :active, :product_codes,
        category_ids: [], branch_ids: [] ])
      if (codes = permitted.delete(:product_codes))
        found = codes.split(/[\s,]+/).compact_blank.map { Current.account.products.find_by_code(_1) }
        permitted[:product_ids] = found.compact.map(&:id)
        @missing_codes = codes.split(/[\s,]+/).compact_blank.zip(found).filter_map { |code, product| code unless product }
      end
      permitted
    end
end
