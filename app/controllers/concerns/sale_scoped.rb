module SaleScoped
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell, :set_sale
  end

  private
    def set_sale
      @sale = Current.account.sales.find(params[:sale_id])
    end
end
