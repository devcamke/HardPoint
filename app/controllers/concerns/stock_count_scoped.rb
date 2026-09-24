module StockCountScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_stock_count
  end

  private
    def set_stock_count
      @count = Current.account.stock_counts.find(params[:stock_count_id])
    end

    def ensure_counting
      redirect_to @count, alert: "This stock take is #{@count.status.humanize.downcase}.", status: :see_other unless @count.counting?
    end
end
