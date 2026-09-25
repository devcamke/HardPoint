# Stock takes being counted, and counting one by scanning shelf by shelf. Counts on the phone are
# blind: the person counting doesn't see what the system expects, so they count what's there.
class Mobile::StockCountsController < Mobile::BaseController
  before_action :ensure_can_manage_stock

  def index
    @counts = Current.account.stock_counts.counting.includes(:branch, :category).chronologically
  end

  def show
    @count = Current.account.stock_counts.find(params[:id])
    @recent = @count.lines.counted.includes(product: :unit).order(updated_at: :desc).limit(8)
  end
end
