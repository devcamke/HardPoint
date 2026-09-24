module CustomerOrderScoped
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell, :set_customer_order
  end

  private
    def set_customer_order
      @customer_order = Current.account.customer_orders.find(params[:customer_order_id])
    end
end
