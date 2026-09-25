# The product just scanned in a stock take, ready for its quantity.
class Mobile::CountLinesController < Mobile::BaseController
  include StockCountScoped
  before_action :ensure_can_manage_stock

  def index
    @line = scanned.found? ? @count.lines.includes(product: :unit).find_by(product: scanned.product) : nil
    render :not_found, status: :not_found unless @line
  end
end
