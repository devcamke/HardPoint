class StockCountsController < ApplicationController
  before_action :ensure_can_manage_stock, only: %i[ new create ]

  def index
    @counts = paginate(Current.account.stock_counts.chronologically.includes(:branch, :category, :creator))
  end

  def show
    @count = Current.account.stock_counts.find(params[:id])
    lines = @count.lines.includes(product: :unit).joins(:product).order("products.name")
    lines = case params[:filter]
    when "uncounted" then lines.uncounted
    when "variances" then lines.with_variance
    else lines
    end
    lines = lines.where(product: Current.account.products.search(params[:query]).select(:id)) if params[:query].present?
    @lines = paginate(lines)
  end

  def new
    @count = Current.account.stock_counts.new(branch: selected_branch)
  end

  def create
    @count = Current.account.stock_counts.new(
      branch: Current.account.branches.find(params.dig(:stock_count, :branch_id)),
      category: params.dig(:stock_count, :category_id).presence && Current.account.categories.find(params.dig(:stock_count, :category_id)),
      note: params.dig(:stock_count, :note))

    if @count.save
      redirect_to @count, notice: "Stock take started with #{helpers.pluralize(@count.lines.count, "product")} to count."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
