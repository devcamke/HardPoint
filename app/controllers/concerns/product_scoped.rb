module ProductScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_product
  end

  private
    def set_product
      @product = Current.account.products.find(params[:product_id])
    end

    def redirect_to_product(**flash)
      redirect_to product_path(@product), status: :see_other, **flash
    end
end
